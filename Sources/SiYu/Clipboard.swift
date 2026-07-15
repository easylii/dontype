import AppKit

/// NSPasteboard 不是线程安全的。本 app 有三处会碰系统剪贴板：
/// - `TextGrabber.viaCopy()` 在**后台线程**合成 Cmd+C 后读剪贴板；
/// - `RecallStore.poll()` 在**主线程**每 0.6s 轮询剪贴板；
/// - `Paster` 在主线程写剪贴板。
/// 后台读和主线程读若同时发生，会让 NSPasteboard 内部类型缓存「边重建边枚举」，
/// 触发 `__NSFastEnumerationMutationHandler` → EXC_BAD_ACCESS 崩溃（曾在朗读抓词时崩）。
/// 这里用一把共享锁把每次剪贴板操作串行化；每次持锁都很短（**不**含 viaCopy 的等待循环），既防崩又不卡 UI。
enum Clipboard {
    private static let lock = NSLock()

    /// 在锁内对系统剪贴板做一次操作（快进快出，别在闭包里 sleep）。
    @discardableResult
    static func withLock<T>(_ body: (NSPasteboard) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(NSPasteboard.general)
    }

    static var changeCount: Int { withLock { $0.changeCount } }
    static func readString() -> String? { withLock { $0.string(forType: .string) } }
    static func write(_ text: String) { withLock { pb in pb.clearContents(); pb.setString(text, forType: .string) } }
    static func clear() { withLock { $0.clearContents() } }
}
