import AppKit
import IOKit.hid

/// Apple TV 遥控器原始 HID 读取器（IOHIDManager）。
/// 读 report id=251（0xfb）的 2 个数据字节 → 每个置位的 bit 是一个键（如 "d0.3"）。
/// 这些是 macOS 不消费的「特殊键」（选择/方向/菜单/TV…）；媒体键不走这条（那条归 HotkeyMonitor）。
/// 需要「输入监视 / Input Monitoring」权限。回调在主线程（调度在主 RunLoop）。
final class RemoteHID {
    /// 某键的「按下=true / 抬起=false」边沿。code 如 "d0.3"。
    var onButtonEdge: ((String, Bool) -> Void)?
    /// 当前按住的全部键集合 —— 设置页实时点亮用。
    var onState: ((Set<String>) -> Void)?
    /// 设置页打开时置 true：仍回调 onState 点亮，但 AppDelegate 不执行动作（免得校准时误触发）。
    var suppressed = false
    /// 诊断：把遥控器「所有」报文（不只 id=251）都写进日志 —— 用来看触摸面有没有发坐标。
    var logAll = false

    static let reportID = 251

    // 遥控器识别：名字含 "Remote"（老情况）失效后（重新配对后蓝牙名会变成序列号），改按 Apple 厂商 + 产品号认。
    static let appleHIDVendor = 1452          // 0x05AC，IOHIDManager 用
    static let siriRemotePID  = 33028         // 0x8104，Siri Remote 的 HID 产品号
    static let appleBTVendor  = "0x004C"      // system_profiler 蓝牙厂商号
    static let siriRemoteBTPID = "0x0314"     // system_profiler 蓝牙产品号

    /// 遥控器各键的标准定义（同型号 Apple TV Remote 的 id=251 位码一致，故可内置默认）。
    struct Btn { let code: String; let id: String; let zh: String; let en: String; let def: String }
    static let buttons: [Btn] = [
        Btn(code: "d0.3", id: "select", zh: "中间（触摸板按下）", en: "Center (OK)", def: "click"),
        Btn(code: "d1.1", id: "up",     zh: "上",          en: "Up",         def: "up"),       // ↑ 列表上一项
        Btn(code: "d1.3", id: "down",   zh: "下",          en: "Down",       def: "down"),     // ↓ 列表下一项
        Btn(code: "d1.4", id: "left",   zh: "左",          en: "Left",       def: "tabPrev"),  // Shift+Tab 上一个控件
        Btn(code: "d1.2", id: "right",  zh: "右",          en: "Right",      def: "tabNext"),  // Tab 下一个控件
        Btn(code: "d0.0", id: "tv",     zh: "TV 键",        en: "TV",         def: "dictation"),
        Btn(code: "d0.6", id: "menu",   zh: "返回 / 退出键", en: "Back",       def: "cancel"),
        Btn(code: "d1.0", id: "b3",     zh: "键3",          en: "Button 3",   def: "none"),
        Btn(code: "d0.7", id: "b4",     zh: "键4",          en: "Button 4",   def: "none"),
        Btn(code: "d0.1", id: "bar",    zh: "长条键",        en: "Bar",        def: "none"),
        Btn(code: "d0.4", id: "power",  zh: "电源 / 顶键",   en: "Power",      def: "none"),
        Btn(code: "d0.5", id: "side",   zh: "侧键",          en: "Side",       def: "assistant"),  // 唤起语音助手
    ]
    /// 可分配的动作。
    static let actions: [(id: String, zh: String, en: String)] = [
        ("none",       "（无）",         "None"),
        ("dictation",  "开始 / 结束听写", "Toggle dictation"),
        ("cancel",     "取消听写",       "Cancel dictation"),
        ("up",         "方向键 ↑",       "Arrow Up"),
        ("down",       "方向键 ↓",       "Arrow Down"),
        ("left",       "方向键 ←",       "Arrow Left"),
        ("right",      "方向键 →",       "Arrow Right"),
        ("tabNext",    "Tab 下一个控件",     "Tab (next)"),
        ("tabPrev",    "Shift+Tab 上一个控件", "Shift+Tab (prev)"),
        ("click",      "OK：发送/激活",   "OK: send/activate"),
        ("readToggle", "朗读 暂停/继续",  "Read pause/resume"),
        ("assistant",  "语音助手 开关",   "Voice assistant on/off"),
    ]
    static func id(forCode code: String) -> String? { buttons.first { $0.code == code }?.id }
    static func defaultAction(_ code: String) -> String { buttons.first { $0.code == code }?.def ?? "none" }

    /// 蓝牙里是否有「已连接」的 Apple TV Remote（system_profiler，不需要任何权限；较慢，建议放后台调）。
    static func isConnectedBT() -> Bool {
        let task = Process()
        task.launchPath = "/usr/sbin/system_profiler"
        task.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = Pipe()
        do { try task.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let arr = json["SPBluetoothDataType"] as? [[String: Any]], let bt = arr.first,
              let conn = bt["device_connected"] as? [[String: Any]] else { return false }
        // 认遥控器：名字含 "Remote"（老情况），或 Apple 厂商 + Siri Remote 产品号（重新配对后名字会变成序列号）。
        return conn.contains { entry in
            entry.contains { name, value in
                if name.localizedCaseInsensitiveContains("Remote") { return true }
                guard let info = value as? [String: Any] else { return false }
                let vid = (info["device_vendorID"] as? String) ?? ""
                let pid = (info["device_productID"] as? String) ?? ""
                return vid.localizedCaseInsensitiveContains("004C") && pid.localizedCaseInsensitiveContains("0314")
            }
        }
    }

    static var hasAccess: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }
    static func requestAccess() { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

    private var manager: IOHIDManager?
    private var activeSet = Set<String>()
    private var buffers: [UnsafeMutablePointer<UInt8>] = []

    var isRunning: Bool { manager != nil }

    /// 有权限就启动监听（幂等）；没权限先弹授权，授权后再调一次即可。
    func start() {
        guard manager == nil, RemoteHID.hasAccess else {
            if manager == nil { RemoteHID.requestAccess() }
            return
        }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, nil)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { context, _, _, device in
            guard let context else { return }
            Unmanaged<RemoteHID>.fromOpaque(context).takeUnretainedValue().attach(device)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = m
        FileLog.write("🎛 RemoteHID 启动（输入监视已授权）")
    }

    private func attach(_ device: IOHIDDevice) {
        let name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? ""
        let vid  = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int) ?? 0
        let pid  = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int) ?? 0
        // 名字含 Remote（老情况），或 Apple 厂商 + Siri Remote 产品号（重新配对后名字变序列号）—— 过滤鼠标/键盘
        guard name.localizedCaseInsensitiveContains("Remote")
                || (vid == RemoteHID.appleHIDVendor && pid == RemoteHID.siriRemotePID) else { return }
        FileLog.write(String(format: "🎛 接管遥控器接口 name=%@ vid=0x%x pid=0x%x", name, vid, pid))
        dumpInfo(device)                                  // 打印这个接口的 usage + 输入元素（看有没有触摸/坐标）
        let len = 64
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: len)
        buffers.append(buf)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buf, len, { context, _, _, _, reportID, reportPtr, reportLen in
            guard let context else { return }
            Unmanaged<RemoteHID>.fromOpaque(context).takeUnretainedValue()
                .onReport(id: Int(reportID), ptr: reportPtr, len: reportLen)
        }, ctx)
    }

    /// 报文入口：诊断时全记；id=251 正常解码。
    private func onReport(id: Int, ptr: UnsafeMutablePointer<UInt8>, len: Int) {
        if logAll {
            var hex = ""
            for i in 0..<min(len, 32) { hex += String(format: "%02x ", ptr[i]) }
            FileLog.write("🎛 报文 id=\(id) len=\(len): \(hex)")
        }
        guard id == RemoteHID.reportID, len >= 3 else { return }
        handle(b0: ptr[1], b1: ptr[2])
    }

    /// 枚举接口能力：主 usage + 输入元素的 usagePage/usage。
    /// 关注 0x0D=数字化仪(触摸)、0x01/0x30·0x31=X/Y 坐标 —— 有就说明硬件采集了触摸位置。
    private func dumpInfo(_ device: IOHIDDevice) {
        let up = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int) ?? 0
        let u  = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int) ?? 0
        FileLog.write(String(format: "🎛 遥控器接口 usagePage=0x%x usage=0x%x", up, u))
        guard let els = IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement] else { return }
        var seen = Set<String>()
        for e in els {
            let t = IOHIDElementGetType(e)
            guard t == kIOHIDElementTypeInput_Misc || t == kIOHIDElementTypeInput_Button
                    || t == kIOHIDElementTypeInput_Axis else { continue }
            let eup = IOHIDElementGetUsagePage(e), eu = IOHIDElementGetUsage(e)
            let key = String(format: "%x/%x", eup, eu)
            if seen.insert(key).inserted {
                FileLog.write(String(format: "    元素 usagePage=0x%x usage=0x%x", eup, eu))
            }
        }
    }

    /// 在主 RunLoop 上被调用 → 直接在主线程更新。
    private func handle(b0: UInt8, b1: UInt8) {
        var now = Set<String>()
        for bit in 0..<8 where b0 & (1 << bit) != 0 { now.insert("d0.\(bit)") }
        for bit in 0..<8 where b1 & (1 << bit) != 0 { now.insert("d1.\(bit)") }
        let downs = now.subtracting(activeSet)
        let ups = activeSet.subtracting(now)
        activeSet = now
        for c in downs { onButtonEdge?(c, true) }
        for c in ups { onButtonEdge?(c, false) }
        onState?(now)
    }
}
