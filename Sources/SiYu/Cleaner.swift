import Foundation

/// 把口语转写交给 AI 整理。优先级：
/// 1. API key（Haiku，~0.5s）→ 2. Claude Code CLI → 3. Codex CLI（都走订阅，~7s）→ 4. 原样返回
enum Cleaner {
    /// 菜单/向导展示用：当前会用哪个整理后端
    static func backendName(config: Config) -> String {
        if !config.cleanup { return L.t(zh: "已停用", en: "Disabled") }
        if let k = config.apiKey, !k.isEmpty { return L.t(zh: "Claude API（最快）", en: "Claude API (fastest)") }
        if claudeCLI != nil { return "Claude Code" }
        if codexCLI != nil { return "Codex" }
        return L.t(zh: "无（装 Claude Code 或 Codex 后自动启用）",
                   en: "None (install Claude Code or Codex)")
    }

    /// 是否有可用整理后端（开启清洗且 API key / Claude Code / Codex 至少其一）。
    static func backendAvailable(config: Config) -> Bool {
        guard config.cleanup else { return false }
        if let k = config.apiKey, !k.isEmpty { return true }
        return claudeCLI != nil || codexCLI != nil
    }

    /// 启发式判断：有口水词/重复才走 Claude，干净的直接出。中英都覆盖。
    static func needsCleanup(_ text: String) -> Bool {
        // 复合口水词（出现即算）
        let compound = ["呃那个", "嗯嗯", "就是说", "反正就是", "然后然后",
                        "就是就是", "那个那个", "对对对", "好好好", "这个这个"]
        if compound.contains(where: { text.contains($0) }) { return true }

        // 单字口水词出现 ≥2 次
        for f in ["呃", "嗯"] {
            if text.components(separatedBy: f).count - 1 >= 2 { return true }
        }

        // 英文口水词/口语连接词（小写边界匹配）
        let lower = " " + text.lowercased() + " "
        let enFillers = [" um ", " uh ", " erm ", " you know ", " i mean ", " sort of ", " kind of "]
        if enFillers.contains(where: { lower.contains($0) }) { return true }
        // " like " 单独太常见，要求出现 ≥2 次才算口水
        if lower.components(separatedBy: " like ").count - 1 >= 2 { return true }

        // 连续重复：2–4 字相邻重复（卡顿/重说）
        let chars = Array(text)
        for len in 2...4 {
            guard chars.count >= len * 2 else { continue }
            for i in 0...(chars.count - len * 2) {
                if String(chars[i..<i+len]) == String(chars[i+len..<i+len*2]) { return true }
            }
        }
        return false
    }

    static func clean(_ text: String, config: Config, completion: @escaping (String) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // config.cleanup = false → 永不整理；true → 自动判断（有口水词/重复才走 Claude）
        guard config.cleanup, !trimmed.isEmpty, needsCleanup(trimmed) else {
            FileLog.write("整理：跳过（原文已整洁）")
            completion(trimmed)
            return
        }
        // 整理用的 system prompt 按识别语言选（保持与原文相同语言输出）
        let sys = systemPrompt(for: config.recognitionLang)
        // 运行时降级链：每一档「跑失败」（断网/未登录/超时/空输出）都自动落到下一档，
        // 最后兜底原文直出。各后端回调 nil 表示失败、应继续往下试。
        if let key = config.apiKey, !key.isEmpty {
            cleanViaAPI(trimmed, key: key, config: config, sys: sys) { r in
                if let r { completion(r) } else { cliChain(trimmed, config: config, sys: sys, completion: completion) }
            }
        } else {
            cliChain(trimmed, config: config, sys: sys, completion: completion)
        }
    }

    /// Claude Code → 失败则 Codex → 失败则原文
    private static func cliChain(_ trimmed: String, config: Config, sys: String, completion: @escaping (String) -> Void) {
        if let cli = claudeCLI {
            cleanViaClaudeCode(trimmed, cli: cli, model: cliAlias(for: config.model), sys: sys) { r in
                if let r { completion(r) }
                else { FileLog.write("↪ Claude Code 失败，转 Codex"); codexChain(trimmed, sys: sys, completion: completion) }
            }
        } else {
            codexChain(trimmed, sys: sys, completion: completion)
        }
    }

    /// Codex → 失败则原文
    private static func codexChain(_ trimmed: String, sys: String, completion: @escaping (String) -> Void) {
        if let cli = codexCLI {
            cleanViaCodex(trimmed, cli: cli, sys: sys) { r in
                if let r { completion(r) }
                else { FileLog.write("↪ Codex 也失败，原文直出"); completion(trimmed) }
            }
        } else {
            FileLog.write("↪ 无可用整理后端，原文直出")
            completion(trimmed)
        }
    }

    /// 完整模型 id → claude CLI 的别名（haiku/sonnet/opus）
    private static func cliAlias(for model: String) -> String {
        if model.contains("opus") { return "opus" }
        if model.contains("sonnet") { return "sonnet" }
        return "haiku"
    }

    /// 成功回调整理后的文本；断网/非 200/无内容回调 nil（交给下一档）
    private static func cleanViaAPI(_ trimmed: String, key: String, config: Config, sys: String,
                                    completion: @escaping (String?) -> Void) {

        let body: [String: Any] = [
            "model": config.model,
            "max_tokens": 1024,
            "system": sys,
            "messages": [["role": "user", "content": trimmed]]
        ]
        guard let url = URL(string: "https://api.anthropic.com/v1/messages"),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion(nil); return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = data

        let t0 = Date()
        URLSession.shared.dataTask(with: req) { data, _, err in
            var out: String? = nil
            if let data,
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let content = json["content"] as? [[String: Any]],
               let first = content.first(where: { ($0["type"] as? String) == "text" }),
               let t = first["text"] as? String {
                let cleaned = t.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { out = cleaned }
            }
            if out == nil { FileLog.write("✗ 清洗(API) 失败：\(err?.localizedDescription ?? "无有效内容")") }
            else { FileLog.write("清洗(API) 完成（\(String(format: "%.1f", Date().timeIntervalSince(t0)))s）") }
            DispatchQueue.main.async { completion(out) }
        }.resume()
    }

    // MARK: Claude Code CLI 后端（用本地订阅，免 API key）

    /// 常见安装位置找 claude CLI（App 从 Finder 启动时 PATH 里没有 nvm）
    private static let claudeCLI: String? = {
        let fm = FileManager.default
        var candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            NSHomeDirectory() + "/.local/bin/claude",
        ]
        let nvmBase = NSHomeDirectory() + "/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmBase) {
            for v in versions.sorted().reversed() {
                candidates.append("\(nvmBase)/\(v)/bin/claude")
            }
        }
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }()

    /// 成功回调整理后文本；启动失败/非零退出/超时/空输出回调 nil（交给下一档 Codex）
    private static func cleanViaClaudeCode(_ trimmed: String, cli: String, model: String, sys: String,
                                           completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let t0 = Date()
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: cli)
            // --output-format json：靠结构化 is_error 判断成败（claude 把报错也打到 stdout，
            // 仅看退出码/文本会把报错漏出去），并从 result 取干净正文。
            proc.arguments = [
                "-p", "--output-format", "json", "--model", model,
                "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#,
                "--system-prompt", sys,
                trimmed,
            ]
            // 在 /tmp 跑，避免加载任何项目的 CLAUDE.md；PATH 指向 CLI 所在目录（node 也在那）
            proc.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = (cli as NSString).deletingLastPathComponent + ":/usr/bin:/bin"
            proc.environment = env
            let out = Pipe()
            proc.standardInput = FileHandle.nullDevice   // 关键：不接 stdin，否则 node 版 claude 会等输入而挂起
            proc.standardOutput = out
            proc.standardError = FileHandle.nullDevice   // 不读 stderr：丢弃避免管道写满死锁

            do {
                try proc.run()
            } catch {
                FileLog.write("✗ claude CLI 启动失败：\(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            // 关掉父进程持有的写端，否则 readDataToEndOfFile 等不到 EOF（子进程退出也不返回）
            try? out.fileHandleForWriting.close()
            // 超时保护：30s 没回来就杀掉，当失败处理
            var timedOut = false
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                if proc.isRunning { timedOut = true; proc.terminate() }
            }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            // 解析 JSON：is_error=false 且 result 非空才算成功，否则失败转下一档
            guard !timedOut,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  (json["is_error"] as? Bool) == false,
                  let result = (json["result"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !result.isEmpty
            else {
                let reason = timedOut ? "超时"
                    : ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["result"] as? String
                    ?? "退出码 \(proc.terminationStatus)/无 JSON"
                FileLog.write("✗ 清洗(Claude Code) 失败（\(reason)）")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            FileLog.write("清洗(Claude Code) 完成（\(String(format: "%.1f", Date().timeIntervalSince(t0)))s）")
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: Codex CLI 后端（没装 Claude Code 时的平替，同样走订阅）

    private static let codexCLI: String? = {
        let fm = FileManager.default
        var candidates = [
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
            NSHomeDirectory() + "/.local/bin/codex",
            NSHomeDirectory() + "/.codex/bin/codex",
        ]
        let nvmBase = NSHomeDirectory() + "/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmBase) {
            for v in versions.sorted().reversed() {
                candidates.append("\(nvmBase)/\(v)/bin/codex")
            }
        }
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }()

    /// 成功回调整理后文本；启动失败/非零退出/超时/空输出回调 nil（交给原文兜底）
    private static func cleanViaCodex(_ trimmed: String, cli: String, sys: String,
                                      completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let t0 = Date()
            // codex exec 的最终回复用 --output-last-message 落文件，比解析 stdout 可靠
            let outFile = NSTemporaryDirectory() + "siyu-codex-last.txt"
            try? FileManager.default.removeItem(atPath: outFile)

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: cli)
            proc.arguments = [
                "exec", "--skip-git-repo-check", "-s", "read-only",
                "--output-last-message", outFile,
                sys + "\n\n" + L.t(zh: "口述原文：", en: "Dictated text:") + "\n" + trimmed,
            ]
            proc.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = (cli as NSString).deletingLastPathComponent + ":/usr/bin:/bin"
            proc.environment = env
            proc.standardInput = FileHandle.nullDevice    // 不接 stdin，避免等输入挂起
            proc.standardOutput = FileHandle.nullDevice   // 结果从 outFile 读，stdout/stderr 丢弃避免死锁
            proc.standardError = FileHandle.nullDevice

            do {
                try proc.run()
            } catch {
                FileLog.write("✗ codex CLI 启动失败：\(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            var timedOut = false
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                if proc.isRunning { timedOut = true; proc.terminate() }
            }
            proc.waitUntilExit()
            let cleaned = ((try? String(contentsOfFile: outFile, encoding: .utf8)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !timedOut, proc.terminationStatus == 0, !cleaned.isEmpty else {
                FileLog.write("✗ 清洗(Codex) 失败（\(timedOut ? "超时" : "退出码 \(proc.terminationStatus)/空输出")）")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            FileLog.write("清洗(Codex) 完成（\(String(format: "%.1f", Date().timeIntervalSince(t0)))s）")
            DispatchQueue.main.async { completion(cleaned) }
        }
    }

    /// Typeless 式智能整理：按识别语言选 prompt，但都要求「保持与原文相同的语言」，
    /// 这样自动检测/混说时也不会被强行翻译。
    static func systemPrompt(for lang: String) -> String {
        switch lang {
        case "en":
            return """
            You rewrite voice dictation into clean, ready-to-send writing. The input is a raw \
            speech transcript — usually fragmented, out of order, with restarts, self-corrections \
            and filler. First understand what the speaker actually means, then rewrite it as \
            fluent, complete, well-connected sentences that read naturally as written text.

            Do:
            - Remove fillers, false starts, repetitions and self-corrections (keep only the final intended version).
            - Join loose fragments into full sentences; reorder and rephrase as needed so it flows.
            - Add correct punctuation, capitalization and paragraph breaks.
            - Fix obvious transcription / homophone errors.

            Don't:
            - Don't change the meaning, intent, or the key terms the speaker deliberately chose.
            - Don't add facts, opinions or details that were not said.
            - Don't summarize into bullet points or cut real content.
            - Don't translate — keep the original language (preserve embedded English terms in mixed text).

            Output only the rewritten text — no preamble, no quotes, no explanation.
            """
        default:
            // 中文/日韩/粤语/自动：用中文指令，但明确「保持原文语言」，对非中文输入同样适用
            return """
            你把语音口述改写成可以直接发送的通顺文字。输入是语音转写原文，通常零碎、语序乱、\
            有重说、自我纠正和口水词。先理解说话人到底想表达什么，再把它改写成完整、连贯、\
            读起来自然的书面句子。

            要做：
            - 去掉口水词、重新开头、重复和自我纠正（只保留最后想说的版本）。
            - 把零碎片段连成完整句子；必要时调整语序、重新措辞，让它通顺。
            - 补全标点、大小写和段落。
            - 纠正明显的同音字 / 音译错误。

            不要：
            - 不改变原意、意图和说话人特意用的关键词。
            - 不添加没说过的信息、观点或细节。
            - 不总结成要点列表，不要删掉实质内容。
            - 不翻译——保持与原文相同的语言（中英混排时保留英文原词）。

            只输出改写后的正文，不要任何前后缀、引号或解释。
            """
        }
    }
}
