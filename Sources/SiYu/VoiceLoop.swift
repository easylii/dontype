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

    // VAD（时间制）
    private var heardSpeech = false
    private var lastLoudAt: TimeInterval = 0
    private var listenStartAt: TimeInterval = 0
    private var vadTimer: Timer?
    private var lastLevel: Float = 0   // 最近电平（诊断 + 调阈值）
    private var logTick = 0
    private let onsetLevel: Float = 0.05       // 高于此算「在说话」
    private let pauseSec: TimeInterval = 1.1   // 说完后静音多久判定结束
    private let maxTurnSec: TimeInterval = 30  // 单轮硬上限

    init(workdir: String) {
        assistant = Assistant(workdir: workdir)
        super.init()
        assistant.onReply = { [weak self] text in self?.startSpeaking(text) }
        assistant.onTurnEnd = { [weak self] in            // 没出文本（纯工具/空）也要继续听，别卡死
            guard let self, self.active, self.state == .thinking else { return }
            self.startListening()
        }
        assistant.onError = { [weak self] m in FileLog.write("🤖 助手出错：\(m)"); self?.startListening() }
        speaker.onFinish = { [weak self] in self?.startListening() }   // 念完接着听
        dictation.onLevel = { [weak self] lv in
            guard let self else { return }
            self.lastLevel = lv
            self.onLevel?(lv)
            if self.state == .listening, lv > self.onsetLevel {
                self.heardSpeech = true
                self.lastLoudAt = ProcessInfo.processInfo.systemUptime
            }
        }
    }

    func start() {
        guard !active else { return }
        active = true; config = Config.load()
        startListening()
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
        let now = ProcessInfo.processInfo.systemUptime
        lastLoudAt = now; listenStartAt = now
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
        logTick += 1
        if logTick % 5 == 0 {   // ~0.5s 一条：看电平/底噪/静音时长，用来定阈值
            FileLog.write(String(format: "🎚 VAD lv=%.3f onset=%.3f heard=%@ 静音=%.1fs",
                                 lastLevel, onsetLevel, heardSpeech ? "是" : "否", now - lastLoudAt))
        }
        let endBySilence = heardSpeech && (now - lastLoudAt > pauseSec)
        let endByMax     = heardSpeech && (now - listenStartAt > maxTurnSec)
        if endBySilence || endByMax { FileLog.write("🎚 VAD → 结束本轮（\(endBySilence ? "静音" : "超时")）"); endTurn() }
    }

    // MARK: 想

    private func endTurn() {
        vadTimer?.invalidate(); vadTimer = nil
        state = .thinking
        dictation.stop { [weak self] raw in
            guard let self, self.active else { return }
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { self.startListening(); return }   // 没识别到内容 → 继续听
            FileLog.write("🗣 你：\(t)")
            self.assistant.send(t)
        }
    }

    // MARK: 说

    private func startSpeaking(_ text: String) {
        guard active else { return }
        state = .speaking
        speaker.speak(text, voiceID: config.readVoice, lang: config.readLang, rate: config.readRate)
        // speaker.onFinish → startListening()
    }
}
