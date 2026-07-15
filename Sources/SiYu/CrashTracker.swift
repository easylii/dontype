import AppKit
import Darwin

/// 崩溃 / 异常退出追踪（纯观测，不改任何功能行为）。App 曾多次「突然退出」，
/// 这里让每次退出都在 status.log 里留下可追查的痕迹：
///
/// 1) 启动哨兵 run.lock：启动时写入 pid+时间，正常退出删除。下次启动若发现残留 →
///    上次是异常退出（崩溃 / 被 kill / 断电），自动去 DiagnosticReports 找那之后的
///    Dontype-*.ips，把「异常类型 + 信号 + 崩溃点」摘要写进日志 —— 一打开日志就知道上次怎么死的。
/// 2) 致命信号 last-gasp：SIGSEGV/SIGBUS/SIGABRT/SIGILL/SIGFPE/SIGTRAP 到来时用
///    async-signal-safe 的 write() 在日志追加一行「💥 SIG…」，随后恢复默认处理并 re-raise，
///    系统照常生成 .ips（不吞崩溃，只留标记）。
/// 3) 未捕获 ObjC 异常：记录 name + reason。
/// 4) SIGTERM / SIGINT（pkill、脚本重启、Ctrl-C）转成 NSApp.terminate → 走 applicationWillTerminate
///    （关 disablesleep、清哨兵）——开发期频繁 pkill 重启不会被误判成「异常退出」。
enum CrashTracker {
    private static let lockPath = Config.dir + "/run.lock"
    private static var fd: Int32 = -1
    // 每个信号一条预分配的 C 字符串（信号处理器里禁止分配内存，只能用现成指针 + write()）
    private static var pSEGV: UnsafeMutablePointer<CChar>?
    private static var pBUS:  UnsafeMutablePointer<CChar>?
    private static var pABRT: UnsafeMutablePointer<CChar>?
    private static var pILL:  UnsafeMutablePointer<CChar>?
    private static var pFPE:  UnsafeMutablePointer<CChar>?
    private static var pTRAP: UnsafeMutablePointer<CChar>?
    private static var termSrc: DispatchSourceSignal?
    private static var intSrc: DispatchSourceSignal?

    static func install() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: Config.dir, withIntermediateDirectories: true)

        // —— 1) 上次是不是异常退出 ——
        if let data = fm.contents(atPath: lockPath), let prev = String(data: data, encoding: .utf8) {
            let line = prev.trimmingCharacters(in: .whitespacesAndNewlines)
            let epoch = line.split(separator: " ")
                .first(where: { $0.hasPrefix("epoch=") })
                .flatMap { Double($0.dropFirst(6)) }
                ?? (Date().timeIntervalSince1970 - 3 * 24 * 3600)
            FileLog.write("⚠️ 上次未正常退出（\(line)），查找崩溃报告…")
            summarizeCrashReport(afterEpoch: epoch)
        }
        try? "pid=\(ProcessInfo.processInfo.processIdentifier) epoch=\(Int(Date().timeIntervalSince1970))"
            .write(toFile: lockPath, atomically: true, encoding: .utf8)

        // —— 2) 致命信号 last-gasp ——
        fd = open(FileLog.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        pSEGV = strdup("💥 SIGSEGV — 内存访问崩溃（last-gasp 标记，详见随后的 .ips 摘要）\n")
        pBUS  = strdup("💥 SIGBUS — 总线错误崩溃（last-gasp）\n")
        pABRT = strdup("💥 SIGABRT — abort（多为未捕获异常 / 断言，last-gasp）\n")
        pILL  = strdup("💥 SIGILL — 非法指令（多为 Swift 断言 trap，last-gasp）\n")
        pFPE  = strdup("💥 SIGFPE — 算术异常（last-gasp）\n")
        pTRAP = strdup("💥 SIGTRAP — 调试陷阱 / Swift trap（last-gasp）\n")
        for s in [SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGFPE, SIGTRAP] { signal(s, gasp) }

        // —— 3) 未捕获 ObjC 异常 ——
        NSSetUncaughtExceptionHandler { ex in
            FileLog.write("💥 未捕获 ObjC 异常：\(ex.name.rawValue) — \(ex.reason ?? "")")
        }

        // —— 4) SIGTERM / SIGINT → 正常退出（信号处理器里不能碰 AppKit，用 DispatchSource 转主线程）——
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        termSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSrc?.setEventHandler { FileLog.write("收到 SIGTERM → 正常退出"); NSApp.terminate(nil) }
        termSrc?.resume()
        intSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        intSrc?.setEventHandler { FileLog.write("收到 SIGINT → 正常退出"); NSApp.terminate(nil) }
        intSrc?.resume()

        let df = DateFormatter(); df.dateFormat = "MM-dd HH:mm"
        let build = (try? fm.attributesOfItem(atPath: Bundle.main.executablePath ?? "")[.modificationDate] as? Date)
            .flatMap { $0 }.map { df.string(from: $0) } ?? "?"
        FileLog.write("🚀 启动 pid=\(ProcessInfo.processInfo.processIdentifier) 构建=\(build)（退出追踪：哨兵+信号标记 已开启）")
    }

    /// applicationWillTerminate 里调：删哨兵 = 本次是正常退出。
    static func markCleanExit() {
        try? FileManager.default.removeItem(atPath: lockPath)
    }

    /// 信号处理器：只做 async-signal-safe 的事（write/fsync/signal/raise），然后交还默认处理生成 .ips。
    private static let gasp: @convention(c) (Int32) -> Void = { s in
        var p: UnsafeMutablePointer<CChar>?
        switch s {
        case SIGSEGV: p = pSEGV
        case SIGBUS:  p = pBUS
        case SIGABRT: p = pABRT
        case SIGILL:  p = pILL
        case SIGFPE:  p = pFPE
        case SIGTRAP: p = pTRAP
        default: p = nil
        }
        if let p, fd >= 0 {
            _ = write(fd, p, strlen(p))
            _ = fsync(fd)
        }
        signal(s, SIG_DFL)
        raise(s)
    }

    /// 从 DiagnosticReports 里找 afterEpoch 之后最新的 Dontype-*.ips，把关键信息摘成一行日志。
    private static func summarizeCrashReport(afterEpoch: TimeInterval) {
        let dir = NSHomeDirectory() + "/Library/Logs/DiagnosticReports"
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else {
            FileLog.write("（读不到 DiagnosticReports，跳过崩溃报告摘要）"); return
        }
        var best: (path: String, name: String, mtime: Date)?
        for n in names where n.hasPrefix("Dontype-") && n.hasSuffix(".ips") {
            let p = dir + "/" + n
            guard let m = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date,
                  m.timeIntervalSince1970 > afterEpoch - 60 else { continue }
            if best == nil || m > best!.mtime { best = (p, n, m) }
        }
        guard let best else {
            FileLog.write("上次异常退出但没有对应崩溃报告 —— 多半是被 kill -9 / 强制退出 / 断电，不是崩溃")
            return
        }
        // .ips = 第一行元数据 JSON + 其余主体 JSON
        guard let raw = try? String(contentsOfFile: best.path, encoding: .utf8),
              let nl = raw.firstIndex(of: "\n"),
              let body = try? JSONSerialization.jsonObject(
                  with: Data(String(raw[raw.index(after: nl)...]).utf8)) as? [String: Any] else {
            FileLog.write("💥 上次崩溃报告：\(best.name)（解析失败，请手动查看）"); return
        }
        let exc = body["exception"] as? [String: Any]
        let type = exc?["type"] as? String ?? "?"
        let sig = exc?["signal"] as? String ?? "?"
        let subtype = exc?["subtype"] as? String ?? ""
        // 崩溃线程里第一个落在本 app 镜像的符号 = 崩溃点
        var at = ""
        if let ft = body["faultingThread"] as? Int,
           let threads = body["threads"] as? [[String: Any]], ft < threads.count,
           let frames = threads[ft]["frames"] as? [[String: Any]],
           let imgs = body["usedImages"] as? [[String: Any]] {
            for f in frames {
                guard let ii = f["imageIndex"] as? Int, ii >= 0, ii < imgs.count,
                      let nm = imgs[ii]["name"] as? String, nm == "Dontype",
                      let sym = f["symbol"] as? String else { continue }
                at = " @ \(sym)"
                break
            }
        }
        FileLog.write("💥 上次崩溃：\(best.name) — \(type)/\(sig) \(subtype)\(at)")
    }
}
