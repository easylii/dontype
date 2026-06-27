import Foundation
import Speech
import AVFoundation

/// 录音 + 语音识别，双后端：
/// - whisper（首选）：录音存文件，结束后 whisper-cli 批式识别 —— 中英混说效果好
/// - apple（备用）：SFSpeechRecognizer 流式识别 —— whisper 文件缺失时自动回退
final class Dictation: NSObject {
    private(set) var isRecording = false
    /// 实时音量电平 0~1（主线程回调），驱动声波动画
    var onLevel: ((Float) -> Void)?
    /// 录音中识别出错（主线程回调），调用方应复位 UI；麦克风已在内部释放
    var onError: ((String) -> Void)?
    /// 本次录音用的麦克风分类（驱动药丸图标）
    private(set) var sourceKind: MicSourceKind = .off

    private enum Backend { case whisper, apple }
    private var backend: Backend = .apple

    private let engine = AVAudioEngine()
    private var tapInstalled = false

    // whisper 后端：录音文件
    private let cafPath = NSTemporaryDirectory() + "siyu-rec.caf"
    private var audioFile: AVAudioFile?

    // apple 后端
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var pending: ((String) -> Void)?

    enum DictationError: LocalizedError {
        case unavailable
        case notAuthorized
        case noMicrophone
        var errorDescription: String? {
            switch self {
            case .unavailable: return "当前语言的语音识别不可用"
            case .notAuthorized: return "未授权语音识别（请在系统设置中允许）"
            case .noMicrophone: return "没有可用的麦克风"
            }
        }
    }

    func requestPermission(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            FileLog.write("语音识别授权状态：\(status.rawValue) (3=已授权)")
            DispatchQueue.main.async { done(status == .authorized) }
        }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            FileLog.write("麦克风授权：\(granted ? "已允许" : "被拒绝")")
        }
    }

    func start(locale: String, micUID: String = "") throws {
        backend = Whisper.available ? .whisper : .apple

        let micAuth = AVCaptureDevice.authorizationStatus(for: .audio)
        FileLog.write("开始录音：后端=\(backend == .whisper ? "whisper" : "apple") 麦克风授权=\(micAuth.rawValue)(3=OK)")

        // 智能选麦：盖开用内置，合盖用 iPhone，兜底系统默认；一个都没有就报错
        guard let p0 = AudioDevices.pick(preferredUID: micUID) else {
            sourceKind = .off
            FileLog.write("✗ 没有任何可用输入设备")
            throw DictationError.noMicrophone
        }
        var dev = p0.0, why = p0.1
        sourceKind = p0.2

        let input = engine.inputNode
        // 把引擎输入切到选中的设备，并返回该设备的输入格式
        func applyDevice(_ id: AudioDeviceID) -> AVAudioFormat {
            var x = id
            if let au = input.audioUnit {
                _ = AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                         &x, UInt32(MemoryLayout<AudioDeviceID>.size))
            }
            return input.outputFormat(forBus: 0)
        }
        var format = applyDevice(dev.id)
        FileLog.write("麦克风：\(dev.name)（\(why)）")

        // 某些网络摄像头 / 采集卡的麦克风返回无效格式（0 声道或 0 采样率），引擎起不来 →
        // 回退到「自动选麦」（iPhone / 内置 / 系统默认），保证还能录到音。
        if (format.channelCount == 0 || format.sampleRate == 0), !micUID.isEmpty,
           let fb = AudioDevices.pick(preferredUID: "") {
            dev = fb.0; why = fb.1; sourceKind = fb.2
            format = applyDevice(dev.id)
            FileLog.write("✗ 原麦克风格式无效，已回退：\(dev.name)（\(why)）")
        }

        switch backend {
        case .whisper:
            try? FileManager.default.removeItem(atPath: cafPath)
            audioFile = try AVAudioFile(forWriting: URL(fileURLWithPath: cafPath),
                                        settings: format.settings)
        case .apple:
            guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
                throw DictationError.notAuthorized
            }
            let r = SFSpeechRecognizer(locale: Locale(identifier: locale))
            guard let r, r.isAvailable else {
                FileLog.write("✗ 识别器不可用：locale=\(locale)")
                throw DictationError.unavailable
            }
            recognizer = r
            FileLog.write("Apple 识别器就绪：\(locale)，本地识别支持=\(r.supportsOnDeviceRecognition)")
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if r.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
            request = req
            latest = ""
        }

        tapInstalled = true
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            switch self.backend {
            case .whisper: try? self.audioFile?.write(from: buffer)
            case .apple: self.request?.append(buffer)
            }
            // RMS 电平 → 0~1，驱动声波
            if let data = buffer.floatChannelData?[0] {
                let n = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<n { sum += data[i] * data[i] }
                let rms = sqrt(sum / Float(max(n, 1)))
                let level = min(1.0, rms * 18)
                DispatchQueue.main.async { self.onLevel?(level) }
            }
        }
        engine.prepare()
        try engine.start()
        FileLog.write("音频引擎已启动，采样率=\(format.sampleRate)")

        if backend == .apple, let r = recognizer, let req = request {
            task = r.recognitionTask(with: req) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    self.latest = result.bestTranscription.formattedString
                    if result.isFinal {
                        FileLog.write("Apple 识别完成（isFinal）：\(self.latest)")
                        DispatchQueue.main.async { self.finishApple() }
                    }
                }
                if let error {
                    FileLog.write("Apple 识别回调错误：\(error.localizedDescription)")
                    DispatchQueue.main.async {
                        if self.isRecording {
                            self.isRecording = false
                            self.releaseMic()
                            self.task = nil
                            self.request = nil
                            self.onError?(error.localizedDescription)
                        } else {
                            self.finishApple()
                        }
                    }
                }
            }
        }
        isRecording = true
    }

    /// 立刻释放麦克风（移除 tap、停引擎并复位），所有出口共用
    private func releaseMic() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning { engine.stop() }
        engine.reset()
        FileLog.write("麦克风已释放")
    }

    /// 取消录音：麦克风立刻关闭，丢弃内容，不回调任何文本。
    func cancel() {
        guard isRecording else { return }
        isRecording = false
        releaseMic()
        audioFile = nil
        pending = nil
        task?.cancel()
        task = nil
        request = nil
        latest = ""
        FileLog.write("录音已取消")
    }

    /// 停止录音：麦克风立刻关闭，识别完成后回调最终文本。
    func stop(_ completion: @escaping (String) -> Void) {
        guard isRecording else { completion(""); return }
        isRecording = false
        releaseMic()

        switch backend {
        case .whisper:
            audioFile = nil   // 关闭文件句柄
            Whisper.transcribe(caf: cafPath, completion: completion)
        case .apple:
            pending = completion
            request?.endAudio()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.finishApple()
            }
        }
    }

    private func finishApple() {
        guard let c = pending else { return }
        pending = nil
        FileLog.write("最终文本：「\(latest)」")
        c(latest)
        task?.cancel()
        task = nil
        request = nil
    }
}
