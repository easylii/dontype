import AppKit

// 隐藏测试入口：`SiYu --test-clean "口述原文"` 直接跑真实整理链并打印，便于验证后端降级。
if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "--test-clean" {
    let input = CommandLine.arguments.count >= 3 ? CommandLine.arguments[2] : ""
    var cfg = Config.load()
    cfg.apiKey = nil   // 测试默认走 CLI 链（Claude Code → Codex → 原文）
    FileHandle.standardError.write("[test] needsCleanup=\(Cleaner.needsCleanup(input)) backend=\(Cleaner.backendName(config: cfg))\n".data(using: .utf8)!)
    // 跑主 runloop（不能阻塞主线程，否则 completion 的 DispatchQueue.main.async 永远不执行）
    Cleaner.clean(input, config: cfg) { result in
        print(result)
        exit(0)
    }
    RunLoop.main.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// menubar-only：不在 Dock 显示，不抢焦点
app.setActivationPolicy(.accessory)
app.run()
