import Foundation

/// 「在线助手」大脑：把 claude CLI 当成一个持久的流式多轮会话来驱动
/// —— stdin 按行喂 stream-json 用户消息，stdout 按行读 stream-json 事件。
///
/// 阶段①：`--permission-mode plan`（只读：能读文件/探索/回答，但不写、不跑命令），
/// 范围限定在 `--add-dir <workdir>`。后续阶段②再换成「default + MCP 权限工具」做副作用确认。
/// ⚠️ 走云端（你自己的 Claude 账号），与本地私密内核分开，单独 opt-in。
final class Assistant {
    /// 流式：每凑够一句就回调（边生成边朗读，ChatGPT 式低延迟）。
    var onSentence: ((String) -> Void)?
    /// 助手一回合的最终文本（用于显示 / 日志）。
    var onReply: ((String) -> Void)?
    /// 回合中用到的工具（名字, 简述）→ 动作日志。
    var onToolUse: ((String, String) -> Void)?
    /// 回合结束（result 事件）。
    var onTurnEnd: (() -> Void)?
    var onError: ((String) -> Void)?
    private(set) var running = false

    private var proc: Process?
    private var stdinHandle: FileHandle?
    private var buffer = Data()
    private var turnText = ""
    private var sentenceBuf = ""        // 流式增量缓冲：凑够一句就 onSentence
    private let workdir: String

    init(workdir: String) { self.workdir = workdir }

    /// 启动持久会话进程（幂等）。
    func start() {
        guard !running else { return }
        guard let cli = Cleaner.claudePath else { onError?("找不到 claude CLI（装 Claude Code 后重试）"); return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli)
        p.currentDirectoryURL = URL(fileURLWithPath: workdir)
        p.arguments = ["-p", "--verbose",
                       "--model", "haiku",                   // 对话用 Haiku：快问快答最快
                       "--include-partial-messages",         // 流式增量 → 边出字边按句朗读
                       // 当成快问快答的语音助手：直接作答、别探索读文件（省掉工具往返 = 思考更快），纯文本
                       "--append-system-prompt",
                       "You are a fast voice assistant. Reply concisely in 1–2 short sentences, in the same language the user spoke. Answer directly from what you already know — do NOT read files, search, run commands, or use any tools unless the user explicitly asks. Plain text only, no markdown.",
                       "--input-format", "stream-json",
                       "--output-format", "stream-json",
                       "--permission-mode", "plan",          // 阶段①：只读，不执行副作用
                       "--add-dir", workdir]
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            DispatchQueue.main.async { self?.ingest(d) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { h in            // stderr：别再吞错误
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return }
            FileLog.write("🤖 stderr: \(s.prefix(300))")
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.running = false }
        }
        do { try p.run() } catch { onError?("启动失败：\(error.localizedDescription)"); return }
        proc = p; stdinHandle = inPipe.fileHandleForWriting; running = true
        FileLog.write("🤖 在线助手会话启动（plan 只读，dir=\(workdir)）")
    }

    /// 发一条用户消息（一回合）。
    func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if !running { start() }
        guard let h = stdinHandle else { onError?("会话未就绪"); return }
        turnText = ""; sentenceBuf = ""
        let msg: [String: Any] = ["type": "user",
                                  "message": ["role": "user", "content": [["type": "text", "text": t]]]]
        guard var line = try? JSONSerialization.data(withJSONObject: msg) else { return }
        line.append(0x0A)
        h.write(line)
    }

    func stop() {
        proc?.terminate(); proc = nil; stdinHandle = nil; running = false; buffer.removeAll()
    }

    // MARK: 解析 stdout 的 stream-json（按行）

    private func ingest(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard !lineData.isEmpty,
                  let o = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any],
                  let type = o["type"] as? String else { continue }
            switch type {
            case "stream_event":   // 流式增量：累加文本 delta → 凑够一句就朗读
                guard let ev = o["event"] as? [String: Any], (ev["type"] as? String) == "content_block_delta",
                      let delta = ev["delta"] as? [String: Any], (delta["type"] as? String) == "text_delta",
                      let t = delta["text"] as? String else { break }
                sentenceBuf += t
                flushSentences(force: false)
            case "assistant":
                guard let msg = o["message"] as? [String: Any],
                      let content = msg["content"] as? [[String: Any]] else { break }
                for b in content {
                    switch b["type"] as? String {
                    case "text":      if let t = b["text"] as? String { turnText += t }
                    case "tool_use":  if let name = b["name"] as? String { onToolUse?(name, brief(b["input"])) }
                    default: break
                    }
                }
            case "result":
                flushSentences(force: true)    // 把最后不带句号的残句也念出来
                let final = (o["result"] as? String) ?? turnText
                FileLog.write("🤖 回复(\(final.count)字): \(final.prefix(60))")
                if !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { onReply?(final) }
                onTurnEnd?()
            case "system":
                if (o["subtype"] as? String) == "error", let m = o["message"] as? String { onError?(m) }
            default: break
            }
        }
    }

    /// 从增量缓冲切出完整句子逐句回调；force=true 把最后不带句末标点的残句也吐出。
    private func flushSentences(force: Bool) {
        let enders: Set<Character> = ["。", "！", "？", "!", "?", "；", ";", ".", "\n"]
        while let idx = sentenceBuf.firstIndex(where: { enders.contains($0) }) {
            let upTo = sentenceBuf.index(after: idx)
            let s = sentenceBuf[..<upTo].trimmingCharacters(in: .whitespacesAndNewlines)
            sentenceBuf = String(sentenceBuf[upTo...])
            if !s.isEmpty { onSentence?(s) }
        }
        if force {
            let rest = sentenceBuf.trimmingCharacters(in: .whitespacesAndNewlines)
            sentenceBuf = ""
            if !rest.isEmpty { onSentence?(rest) }
        }
    }

    /// 工具输入的一行简述（动作日志用）。
    private func brief(_ input: Any?) -> String {
        guard let dict = input as? [String: Any] else { return "" }
        for k in ["file_path", "path", "pattern", "command", "query", "url", "prompt"] {
            if let v = dict[k] as? String { return v.count > 80 ? String(v.prefix(80)) + "…" : v }
        }
        return ""
    }
}
