import AppKit
import CoreGraphics

/// 简易文件日志：unified log 收录不稳定，诊断直接看 ~/.config/siyu/status.log。
enum FileLog {
    static let path = Config.dir + "/status.log"
    static func write(_ msg: String) {
        let line = "\(Date()) \(msg)\n"
        try? FileManager.default.createDirectory(atPath: Config.dir, withIntermediateDirectories: true)
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8)!)
            h.closeFile()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}

/// 一个「双击修饰键」触发器的定义。
struct Trigger {
    let id: String          // 配置里存的标识，如 "control"
    let label: String       // 给用户看的名字，如 "Control"
    let keycodes: Set<Int64> // 接受的物理键 keycode（左右两侧都算）
    let mask: CGEventFlags   // 对应的修饰键 flag

    static let all: [Trigger] = [
        Trigger(id: "control", label: "Control", keycodes: [59, 62], mask: .maskControl),
        Trigger(id: "fn", label: "Fn (🌐)", keycodes: [63], mask: .maskSecondaryFn),
        Trigger(id: "rightCommand", label: "右 ⌘", keycodes: [54], mask: .maskCommand),
        Trigger(id: "rightOption", label: "右 Option", keycodes: [61], mask: .maskAlternate),
        Trigger(id: "option", label: "Option", keycodes: [58, 61], mask: .maskAlternate),
    ]

    static func from(_ id: String) -> Trigger {
        all.first { $0.id == id } ?? all[0]
    }
}

/// 监听全局「双击某修饰键」手势：该键单独按下又松开、中途没碰别的键算一次 tap，
/// 0.4s 内两次 = 触发。需要「辅助功能」权限。
final class HotkeyMonitor {
    /// 录音中触发键「按下」立即回调（不等抬起，响应最快）—— 主线程
    var onSingleTap: (() -> Void)?
    /// 待命时 0.4s 内两次纯 tap 回调（双击开始）—— 主线程
    var onDoubleTap: (() -> Void)?
    /// 录音中按 Esc 的回调 —— 主线程；recordingActive 为 true 时 Esc 被吞掉不传给前台 App
    var onEscape: (() -> Void)?
    /// 录音会话进行中（影响：触发键按下即停、Esc 被接管）
    var recordingActive = false
    /// 测试模式：检测到双击只回调 onTestDoubleTap、不触发录音（热键设置窗口用）
    var testMode = false
    /// 测试模式下检测到双击触发键 —— 主线程
    var onTestDoubleTap: (() -> Void)?
    private(set) var trigger: Trigger = .from("control")

    private var tap: CFMachPort?
    private var thread: Thread?
    private var keyHeld = false
    private var sawOther = false
    private var lastTapTime: TimeInterval = 0

    private let allModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]

    func setTrigger(_ t: Trigger) {
        trigger = t
        keyHeld = false
        sawOther = false
    }

    func start() {
        guard tap == nil else { return }   // 已在监听，避免重复创建
        let mask = (1 << CGEventType.flagsChanged.rawValue) |
                   (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let m = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            return m.handle(type: type, event: event) ? Unmanaged.passUnretained(event) : nil
        }
        // 用 .defaultTap 而非 .listenOnly：listen-only 键盘监听走「输入监视」权限，
        // defaultTap 走「辅助功能」权限（我们已申请的就是它）。事件原样放行，不做修改。
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            FileLog.write("✗ 事件监听创建失败（辅助功能权限未生效）AXTrusted=\(AXIsProcessTrusted())")
            return
        }
        FileLog.write("✓ 事件监听已启动，触发键：双击 \(trigger.label)，AXTrusted=\(AXIsProcessTrusted())")
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        // 专用线程跑事件监听：主线程再忙（识别/UI/网络回调）也不影响按键响应
        let t = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        t.name = "SiYu.EventTap"
        t.qualityOfService = .userInteractive
        t.start()
        thread = t
    }

    var isActive: Bool { tap != nil }

    /// 返回 false 表示吞掉该事件（仅用于录音中的 Esc）
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }

        if type == .keyDown {
            let kc = event.getIntegerValueField(.keyboardEventKeycode)
            if kc == 53, recordingActive {    // Esc：录音中接管，事件不下传
                FileLog.write("Esc")
                DispatchQueue.main.async { self.onEscape?() }
                return false
            }
            if keyHeld { sawOther = true }   // 触发键按住期间敲了别的键 → 不算纯 tap
            return true
        }

        // flagsChanged
        let kc = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        guard trigger.keycodes.contains(kc) else {
            // 别的修饰键变化；若触发键正按着，标记为不纯
            if keyHeld { sawOther = true }
            return true
        }

        let pressed = flags.contains(trigger.mask)
        var withoutOurs = flags
        withoutOurs.remove(trigger.mask)
        let hasOtherModifier = !withoutOurs.intersection(allModifiers).isEmpty

        // 录音中：触发键「按下」瞬间即停，不等抬起、不要求纯净点击 —— 最灵敏
        if pressed && recordingActive {
            FileLog.write("⏹ \(trigger.label) 按下 → 停止")
            keyHeld = false
            lastTapTime = 0
            DispatchQueue.main.async { self.onSingleTap?() }
            return true
        }

        if pressed && !keyHeld {
            keyHeld = true
            sawOther = hasOtherModifier
        } else if !pressed && keyHeld {
            keyHeld = false
            if !sawOther { registerTap() }
        }
        return true
    }

    /// 消费当前的 tap 计时（单击已被用掉时调用，防止紧接着的下一击被误判为双击）
    func resetTapState() {
        lastTapTime = 0
    }

    private func registerTap() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastTapTime < 0.4 {
            lastTapTime = 0
            FileLog.write("●● 双击 \(trigger.label)")
            // 测试模式只回调测试钩子、不开始录音；正常模式走 onDoubleTap
            if testMode {
                DispatchQueue.main.async { self.onTestDoubleTap?() }
            } else {
                DispatchQueue.main.async { self.onDoubleTap?() }
            }
        } else {
            lastTapTime = now
            FileLog.write("● 单击 \(trigger.label)")
        }
    }
}
