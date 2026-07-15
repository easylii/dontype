import AppKit
import ApplicationServices

/// 取「当前选中的文字」，覆盖所有 app：
/// 1. 辅助功能 `kAXSelectedText`（原生 app：Safari/备忘录/Mail/TextEdit… ）—— 不动剪贴板，最干净。
/// 2. 拿不到（终端里的 Claude Code / VS Code / 部分网页）则模拟 Cmd+C 读剪贴板，**读完还原**用户原本的剪贴板。
/// 含轮询等待，应在后台线程调用（别卡主线程）。需要「辅助功能」权限。
enum TextGrabber {
    static func selectedText() -> String? {
        if let t = viaAX() { return t }
        return viaCopy()
    }

    /// 「从 highlight 往下读」：焦点文本元素的全文（kAXValue）+ 选区起点（kAXSelectedTextRange），
    /// 返回从选区起点到该元素结尾的文字（= 从你选的地方一直到这个文本块/section 的末尾）。
    /// 只有暴露这两个属性的原生文本控件可用；拿不到返回 nil，调用方退回只读选中。
    static func selectionToBlockEnd() -> String? {
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        let sys = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let r1 = AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focused)
        guard r1 == .success, let focusedRef = focused else {
            FileLog.write("往下读✗[\(app)]：拿不到焦点元素 (err \(r1.rawValue))"); return nil
        }
        let el = focusedRef as! AXUIElement

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleRef as? String) ?? "?"

        var valueRef: CFTypeRef?
        let r2 = AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valueRef)
        guard r2 == .success, let full = valueRef as? String, !full.isEmpty else {
            FileLog.write("往下读✗[\(app)]：kAXValue 取不到（退回只读选中）role=\(role) err=\(r2.rawValue)"); return nil
        }

        var rangeRef: CFTypeRef?
        let r3 = AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        guard r3 == .success else {
            FileLog.write("往下读✗[\(app)]：选区range取不到 role=\(role) 全文\(full.count)字 err=\(r3.rawValue)"); return nil
        }
        var range = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) else {
            FileLog.write("往下读✗[\(app)]：range解析失败 role=\(role)"); return nil
        }

        // AX 文本偏移是 UTF-16（NSString）单位
        let ns = full as NSString
        let start = max(0, min(range.location, ns.length))
        let sub = ns.substring(from: start).trimmingCharacters(in: .whitespacesAndNewlines)
        FileLog.write("往下读✓[\(app)]：role=\(role) 全文\(ns.length)字 选区起点\(range.location) → 读\(sub.count)字")
        return sub.isEmpty ? nil : sub
    }

    // MARK: 辅助功能直读

    private static func viaAX() -> String? {
        let sys = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedRef = focused else { return nil }
        let el = focusedRef as! AXUIElement
        var sel: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextAttribute as CFString, &sel) == .success,
              let s = sel as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    // MARK: Cmd+C 兜底（读完还原剪贴板）

    private static func viaCopy() -> String? {
        let saved = Clipboard.readString()   // 备份用户原有剪贴板（仅文本，够用）
        let before = Clipboard.changeCount

        sendCmdC()

        // 轮询等待剪贴板更新（最多 ~400ms）；在后台线程，sleep 不卡 UI。
        // 每次读都走 Clipboard 的锁（短持锁），不与主线程的 RecallStore 轮询抢内部缓存。
        var grabbed: String?
        let deadline = Date().addingTimeInterval(0.4)
        while Date() < deadline {
            if Clipboard.changeCount != before { grabbed = Clipboard.readString(); break }
            usleep(20_000)
        }

        // 还原用户原本的剪贴板
        if let saved { Clipboard.write(saved) } else { Clipboard.clear() }

        let t = grabbed?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t?.isEmpty ?? true) ? nil : t
    }

    /// 合成 Cmd+C（与 Paster 的 Cmd+V 同套路：combinedSessionState 源 + cghidEventTap）
    private static func sendCmdC() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let cKey: CGKeyCode = 0x08 // 'c'
        let down = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
