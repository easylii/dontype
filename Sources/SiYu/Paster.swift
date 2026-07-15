import AppKit
import CoreGraphics

/// 复制到剪贴板 / 自动粘贴到当前光标处。
/// 自动粘贴 = 写入剪贴板后合成 Cmd+V。我们的悬浮窗是 nonactivating 面板、不抢焦点，
/// 所以 Cmd+V 会落到用户原来所在的输入框。需要「辅助功能」权限。
enum Paster {
    static func copy(_ text: String) {
        Clipboard.write(text)   // 走共享锁，与后台 viaCopy / RecallStore 轮询串行化
    }

    static func paste(_ text: String) {
        copy(text)
        // 稍等一拍，确保剪贴板写入完成再发按键
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let src = CGEventSource(stateID: .combinedSessionState)
            let vKey: CGKeyCode = 0x09 // 'v'
            let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
            down?.flags = .maskCommand
            let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}
