import Foundation

/// whisper.cpp 本地识别后端：中英混说效果远好于 Apple 单语模型。
/// 常驻 whisper-server（模型加载一次，每次识别 ~1s）；server 不可用时回退一次性 CLI。
/// 二进制：开发目录 → App 内置（Resources/whisper/）。
/// 模型：开发目录 → ~/Library/Application Support/SiYu/（首次/切换时自动下载落这里）。
/// 都缺则 Dictation 自动回退 Apple 后端。
///
/// 模型与识别语言均可在菜单切换：`current` / `lang` 由 config 设定，改动后重启 server 生效。
enum Whisper {
    // MARK: 模型目录

    /// 一个可选识别模型。file 同时是磁盘文件名与 HuggingFace 下载文件名。
    struct Model {
        let id: String        // config.whisperModel 存的值
        let file: String      // ggml-*.bin
        let sizeMB: Int       // 约略大小，给下载提示
        let displayZh: String
        let displayEn: String
        var url: URL {
            URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(file)")!
        }
        var display: String { L.t(zh: displayZh, en: displayEn) }
    }

    /// 菜单里可选的模型，从快到准。turbo 为默认（随 App 分发的就是它）。
    static let models: [Model] = [
        Model(id: "large-v3-turbo", file: "ggml-large-v3-turbo.bin", sizeMB: 1550,
              displayZh: "Large v3 Turbo（默认 · 快而准）", displayEn: "Large v3 Turbo (default · fast)"),
        Model(id: "large-v3", file: "ggml-large-v3.bin", sizeMB: 3100,
              displayZh: "Large v3（最准 · 较慢）", displayEn: "Large v3 (most accurate · slower)"),
        Model(id: "medium", file: "ggml-medium.bin", sizeMB: 1530,
              displayZh: "Medium（折中）", displayEn: "Medium (balanced)"),
        Model(id: "small", file: "ggml-small.bin", sizeMB: 466,
              displayZh: "Small（轻量 · 最省）", displayEn: "Small (light · fastest)"),
    ]

    static func model(for id: String) -> Model {
        models.first { $0.id == id } ?? models[0]
    }

    /// 识别语言：whisper 语言码 + 显示名。auto = 让 whisper 自动检测。
    static let languages: [(code: String, zh: String, en: String)] = [
        ("zh", "中文", "Chinese"),
        ("en", "英语", "English"),
        ("ja", "日语", "Japanese"),
        ("ko", "韩语", "Korean"),
        ("yue", "粤语", "Cantonese"),
        ("auto", "自动检测", "Auto-detect"),
    ]

    static func languageDisplay(_ code: String) -> String {
        if let l = languages.first(where: { $0.code == code }) { return L.t(zh: l.zh, en: l.en) }
        return code
    }

    // MARK: 当前选择（由 config 设定）

    private(set) static var current: Model = models[0]
    private(set) static var lang: String = "zh"

    /// 从 config 设定模型与识别语言（不触发下载、不重启 server——交给调用方编排）。
    static func configure(modelID: String, language: String) {
        current = model(for: modelID)
        lang = language
    }

    // MARK: 路径

    static let devDir = ("~/Documents/SiYu/whisper" as NSString).expandingTildeInPath
    static let supportDir = NSHomeDirectory() + "/Library/Application Support/SiYu"
    static let port = 8178

    /// 识别提示词：按语言给 whisper 一点先验，提升专有名词/中英混排。auto/未知语言留空。
    static var prompt: String {
        switch lang {
        case "zh", "yue": return "以下是简体中文与英文混合的口述内容。"
        case "en": return "The following is dictated English, possibly mixed with technical terms."
        case "ja": return "以下は日本語の口述内容です。"
        case "ko": return "다음은 한국어 받아쓰기 내용입니다."
        default: return ""
        }
    }

    private static func bin(_ name: String) -> String {
        let dev = devDir + "/" + name
        if FileManager.default.isExecutableFile(atPath: dev) { return dev }
        if let bundled = Bundle.main.path(forResource: name, ofType: nil, inDirectory: "whisper") {
            return bundled
        }
        return dev
    }
    static var cli: String { bin("whisper-cli") }
    static var server: String { bin("whisper-server") }

    /// 指定模型的磁盘路径（开发目录优先，否则 Application Support）。
    static func modelPath(_ m: Model) -> String {
        let dev = devDir + "/" + m.file
        if FileManager.default.fileExists(atPath: dev) { return dev }
        return supportDir + "/" + m.file
    }
    static var model: String { modelPath(current) }
    static var modelName: String { current.file }
    static var modelURL: URL { current.url }

    static func isDownloaded(_ m: Model) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(m))
    }

    private static var serverProc: Process?

    static var available: Bool {
        FileManager.default.isExecutableFile(atPath: cli) &&
        FileManager.default.fileExists(atPath: model)
    }

    // MARK: server 生命周期（App 启动时拉起、退出时回收、切换模型/语言时重启）

    static func startServer() {
        guard serverProc == nil,
              FileManager.default.isExecutableFile(atPath: server),
              FileManager.default.fileExists(atPath: model) else { return }

        // 清掉上次异常退出残留的实例（按完整路径匹配，不误伤别的进程）
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        kill.arguments = ["-f", server]
        try? kill.run()
        kill.waitUntilExit()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: server)
        var args = [
            "-m", model,
            "--host", "127.0.0.1", "--port", String(port),
            "-l", lang,
        ]
        if !prompt.isEmpty { args += ["--prompt", prompt] }
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            serverProc = p
            FileLog.write("whisper-server 已启动（pid \(p.processIdentifier)，模型 \(current.id)，语言 \(lang)，加载约 10s）")
        } catch {
            FileLog.write("✗ whisper-server 启动失败：\(error.localizedDescription)，识别将走一次性 CLI")
        }
    }

    static func stopServer() {
        serverProc?.terminate()
        serverProc = nil
    }

    /// 切换模型/语言后调用：停掉旧 server、用新设置重启。模型须已下载。
    static func restartServer() {
        stopServer()
        startServer()
    }

    // MARK: 识别

    /// 后台转码+识别（server 优先，失败回退 CLI），主线程回调最终文本
    static func transcribe(caf: String, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let t0 = Date()
            let wav = NSTemporaryDirectory() + "siyu-rec.wav"
            try? FileManager.default.removeItem(atPath: wav)

            let conv = Process()
            conv.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
            conv.arguments = [caf, wav, "-f", "WAVE", "-d", "LEI16@16000", "-c", "1"]
            conv.standardOutput = Pipe()
            conv.standardError = Pipe()
            do {
                try conv.run()
                conv.waitUntilExit()
            } catch {
                FileLog.write("✗ afconvert 启动失败：\(error.localizedDescription)")
                DispatchQueue.main.async { completion("") }
                return
            }
            guard conv.terminationStatus == 0 else {
                FileLog.write("✗ afconvert 转码失败（status \(conv.terminationStatus)）")
                DispatchQueue.main.async { completion("") }
                return
            }

            transcribeViaServer(wav: wav) { text in
                if let text {
                    FileLog.write("whisper(server) 完成（\(String(format: "%.1f", Date().timeIntervalSince(t0)))s）：「\(text)」")
                    DispatchQueue.main.async { completion(text) }
                } else {
                    // server 没起来/还在加载模型 → 一次性 CLI 兜底
                    let text = transcribeViaCLI(wav: wav)
                    FileLog.write("whisper(cli) 完成（\(String(format: "%.1f", Date().timeIntervalSince(t0)))s）：「\(text)」")
                    DispatchQueue.main.async { completion(text) }
                }
            }
        }
    }

    /// 失败（连接不上/非200）回调 nil；成功回调识别文本
    private static func transcribeViaServer(wav: String, completion: @escaping (String?) -> Void) {
        guard let data = FileManager.default.contents(atPath: wav),
              let url = URL(string: "http://127.0.0.1:\(port)/inference") else {
            completion(nil); return
        }
        let boundary = "siyu-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("response_format", "text")
        field("language", lang)
        if !prompt.isEmpty { field("prompt", prompt) }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"rec.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        URLSession.shared.dataTask(with: req) { data, resp, _ in
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let data, let text = String(data: data, encoding: .utf8) else {
                completion(nil); return
            }
            completion(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }.resume()
    }

    private static func transcribeViaCLI(wav: String) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cli)
        var args = ["-m", model, "-f", wav, "-l", lang, "-nt", "-np"]
        if !prompt.isEmpty { args += ["--prompt", prompt] }
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            FileLog.write("✗ whisper-cli 启动失败：\(error.localizedDescription)")
            return ""
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
