import AppKit

/// 连续语音对话编排器：不用按键、停顿即结束、轮流对话。
/// 听(VAD)→ 想(转写 + Claude)→ 说(TTS)→ 自动回到听。用独立 Dictation/Speaker，不碰本地内核。
/// 阶段①：barge-in（说话时打断）还没做（需回声消除），这版是「停顿轮流」。
final class VoiceLoop: NSObject {
    enum State { case idle, listening, thinking, speaking }
    var onState: ((State) -> Void)?
    var onLevel: ((Float) -> Void)?

    private let dictation = Dictation()
    private let speaker = Speaker()
    private let assistant: Assistant
    private var config = Config.load()
    private(set) var active = false
    private(set) var state: State = .idle { didSet { onState?(state) } }

    // 连续对话：说过话后静音够久就自动判停（不用按键）；说回复时不听（按键打断）。
    private var heardSpeech = false
    private var listenStartAt: TimeInterval = 0
    private var lastVoiceAt: TimeInterval = 0   // 最近一次「在说话」的时刻 → 算静音时长
    private var vadTimer: Timer?
    private let onsetLevel: Float = 0.13        // 高于此算「在说话」（点亮状态球 + 防空轮）
    private let silenceWindow: TimeInterval = 1.5 // 说过话后静音超过这么久 = 说完了
    private let maxTurnSec: TimeInterval = 45   // 单轮硬上限

    init(workdir: String) {
        assistant = Assistant(workdir: workdir)
        super.init()
        assistant.onSentence = { [weak self] s in self?.speakSentence(s) }   // 流式：一句到就念
        assistant.onReply = { text in FileLog.write("🤖 回复：\(text.prefix(80))") }   // 仅日志，朗读走 onSentence
        assistant.onTurnEnd = { [weak self] in
            guard let self, self.active else { return }
            if self.state == .speaking { self.speaker.endStream() }   // 最后一句念完 → onFinish → 待命
            else if self.state == .thinking { self.state = .idle }    // 没出声（纯工具/空）→ 待命
        }
        assistant.onError = { [weak self] m in
            FileLog.write("🤖 助手出错：\(m)")
            if let self, self.active { self.state = .idle }
        }
        speaker.onFinish = { [weak self] in                // 连续：回复念完 → 稍等避开尾音 → 自动接着听
            guard let self, self.active, self.state == .speaking else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.active, self.state == .speaking else { return }
                self.startListening()
            }
        }
        dictation.onLevel = { [weak self] lv in
            guard let self else { return }
            self.onLevel?(lv)
            if self.state == .listening, lv > self.onsetLevel {
                self.heardSpeech = true
                self.lastVoiceAt = ProcessInfo.processInfo.systemUptime
            }
        }
    }

    /// 打开助手到「待命」（显示球、等右侧键说话），不立刻录音。
    func open() {
        guard !active else { return }
        active = true; config = Config.load(); state = .idle
        assistant.start()        // 预热 CLI 进程，藏掉首轮冷启动
    }

    /// 连续对话入口/打断键（遥控器/键盘）：待命 → 进入并开始听；正在听 → 立刻发送；正在念 → 打断（之后自动接着听）。
    func talk() {
        switch state {
        case .listening: endTurn()                          // 立刻发送（不等静音）
        case .thinking:  break                              // 处理中 → 忽略
        case .speaking:  speaker.stop()                     // 打断 → onFinish 自动接着听
        case .idle:
            if !active { active = true; config = Config.load(); assistant.start() }
            startListening()                                // 进入对话、开始听
        }
    }

    /// 键盘「双击」= 进入对话 / 打断（与 talk 同义；待命→开始听，正在念→打断）。
    func beginTalk() {
        switch state {
        case .listening, .thinking: break
        case .speaking: speaker.stop()                      // 打断 → 自动接着听
        case .idle:
            if !active { active = true; config = Config.load(); assistant.start() }
            startListening()
        }
    }

    /// 键盘「单击」= 立刻发送 / 打断（正在听→发送；正在念→打断后自动接着听）。
    func endTalk() {
        switch state {
        case .listening: endTurn()
        case .speaking:  speaker.stop()
        default:         break
        }
    }

    func stop() {
        active = false
        vadTimer?.invalidate(); vadTimer = nil
        if dictation.isRecording { dictation.cancel() }
        if speaker.isSpeaking { speaker.stop() }
        state = .idle
    }

    // MARK: 听

    private func startListening() {
        guard active else { return }
        if speaker.isSpeaking { speaker.stop() }
        heardSpeech = false
        listenStartAt = ProcessInfo.processInfo.systemUptime
        lastVoiceAt = listenStartAt
        dictation.requestPermission { [weak self] ok in
            guard let self, self.active else { return }
            guard ok else { FileLog.write("🤖 缺麦克风权限，停止语音环"); self.stop(); return }
            do { try self.dictation.start(locale: self.config.locale) }
            catch { FileLog.write("🤖 麦克风启动失败：\(error.localizedDescription)"); self.stop(); return }
            self.state = .listening
            self.vadTimer?.invalidate()
            self.vadTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tickVAD() }
        }
    }

    private func tickVAD() {
        guard active, state == .listening else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if heardSpeech, now - listenStartAt > maxTurnSec { endTurn(); return }   // 硬上限兜底
        if heardSpeech, now - lastVoiceAt > silenceWindow { endTurn() }          // 静音判停 → 自动说完
    }

    // MARK: 想

    private func endTurn() {
        vadTimer?.invalidate(); vadTimer = nil
        state = .thinking
        dictation.stop { [weak self] raw in
            guard let self, self.active else { return }
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { self.state = .idle; return }   // 没识别到内容 → 回待命
            FileLog.write("🗣 你：\(t)")
            self.assistant.send(t)
        }
    }

    // MARK: 说

    /// 流式：每来一句就接着念（第一句到了才切到 speaking 并开流），念完最后一句靠 onTurnEnd→endStream 收尾。
    private func speakSentence(_ s: String) {
        guard active else { return }
        if state != .speaking { state = .speaking; speaker.beginStream() }
        speaker.enqueue(s, voiceID: config.readVoice, lang: config.readLang, rate: config.readRate)
    }
}
