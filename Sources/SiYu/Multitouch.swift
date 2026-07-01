import AppKit

/// 用私有 MultitouchSupport 框架读 Siri 遥控器触摸面 → 当触控板移动鼠标。
/// 触摸被 macOS 的 AppleBluetoothMultitouch 驱动收进多点触控子系统，原始 HID 读不到，
/// 但这套 MT API 能拿到连续手指坐标（和读内置触控板同一套）。
/// ⚠️ 私有框架：不能上 App Store，跨系统版本可能变 —— 故做成可开关、默认关。
final class MultitouchRemote {
    private typealias MTRef = UnsafeMutableRawPointer
    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>
    private typealias DeviceFn     = @convention(c) (MTRef, Int32) -> Void          // start / stop
    private typealias RegisterFn   = @convention(c) (MTRef, MTContactCallback) -> Void
    private typealias FamilyFn     = @convention(c) (MTRef, UnsafeMutablePointer<Int32>) -> Int32
    private typealias MTContactCallback =
        @convention(c) (MTRef?, UnsafeRawPointer?, Int32, Double, Int32) -> Int32

    private static let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
    private static let remoteFamily: Int32 = 0x91   // Siri Remote 触摸面（内置触控板是 0x6d）

    private var handle: UnsafeMutableRawPointer?
    private var devices: [MTRef] = []
    private var deviceList: CFArray?          // 保活 MTDeviceCreateList 返回的数组，元素（设备指针）才不悬空
    private(set) var running = false

    // 给 C 回调用的相对移动状态（无捕获 → 必须静态）
    fileprivate static var hasPrev = false
    fileprivate static var prevID: Int32 = -1     // 触点标识：同一根手指连续帧才算移动
    fileprivate static var settle = 0             // 落指/换指后的稳定期帧数（这期间不移动）
    fileprivate static var prevX: Float = 0, prevY: Float = 0
    fileprivate static let src = CGEventSource(stateID: .hidSystemState)
    static var gain: Double = 1100    // 满屏滑动 ≈ 整块触摸面扫一遍
    static var dead: Double = 0.0025  // 软死区：单帧位移幅度小于此值视为手抖、忽略（故意移动通常远大于此）
    fileprivate static var lastMoveAt: TimeInterval = 0   // 最近一次"明显滑动指点"的时刻（单调时钟）
    fileprivate static var gestureAccum: Double = 0       // 本次触摸手势累计移动的光标像素（新触点清零）
    /// 刚用触摸板滑过光标？OK 键据此决定「点光标处(鼠标模式)」还是「激活聚焦控件(键盘模式)」。
    /// 关键：只有累计 ≥25px 的"明显指点滑动"才置位 —— 按 OK 时手指压触摸板的微抖远不到，故不会误判成鼠标模式。
    static var recentlyMoved: Bool { ProcessInfo.processInfo.systemUptime - lastMoveAt < 1.5 }
    /// 最近一次「明显滑动指点」的单调时刻 —— OK 键拿它和「最近一次方向键」比，谁更近就按谁的模式。
    static var lastMoveUptime: TimeInterval { lastMoveAt }

    func start() {
        guard !running else { return }
        guard let h = handle ?? dlopen(MultitouchRemote.path, RTLD_NOW) else {
            FileLog.write("🖐 MultitouchSupport 打不开"); return
        }
        handle = h
        func sym(_ n: String) -> UnsafeMutableRawPointer? { dlsym(h, n) }
        guard let cl = sym("MTDeviceCreateList"), let st = sym("MTDeviceStart"),
              let rg = sym("MTRegisterContactFrameCallback"), let fam = sym("MTDeviceGetFamilyID") else {
            FileLog.write("🖐 MT 符号缺失"); return
        }
        let createList = unsafeBitCast(cl, to: CreateListFn.self)
        let startDev   = unsafeBitCast(st, to: DeviceFn.self)
        let registerCB = unsafeBitCast(rg, to: RegisterFn.self)
        let familyID   = unsafeBitCast(fam, to: FamilyFn.self)

        // ⚠️ 内存：MTDeviceCreateList 的所有权语义在不同 macOS 版本并不一致；用 takeRetainedValue 在
        // 被反复调用时（旧的每 3s 重试）会「过度释放」→ 定时器回调 autorelease 池 pop 时 objc_release 崩溃
        // （EXC_BAD_ACCESS）。改用 takeUnretainedValue（绝不过度释放），并把数组存进 deviceList 保活 ——
        // 只有我们持有数组期间，devices 里的设备指针才不会悬空。
        let arr = createList().takeUnretainedValue()
        var found: [MTRef] = []
        for i in 0..<CFArrayGetCount(arr) {
            guard let dev = UnsafeMutableRawPointer(mutating: CFArrayGetValueAtIndex(arr, i)) else { continue }
            var f: Int32 = 0; _ = familyID(dev, &f)
            guard f == MultitouchRemote.remoteFamily else { continue }   // 只接管遥控器，跳过触控板/其它 MT 设备
            registerCB(dev, MultitouchRemote.contactCB)
            startDev(dev, 0)
            found.append(dev)
        }
        devices = found
        deviceList = found.isEmpty ? nil : arr    // 接管了才留住数组保设备指针；没接管就放掉，不留引用
        MultitouchRemote.hasPrev = false
        running = !devices.isEmpty
        if running { FileLog.write("🖐 遥控器触摸板已接管（→ 鼠标）") }
    }

    func stop() {
        guard running, let h = handle else { return }
        func sym(_ n: String) -> UnsafeMutableRawPointer? { dlsym(h, n) }
        if let sp = sym("MTDeviceStop"), let ur = sym("MTUnregisterContactFrameCallback") {
            let stopDev = unsafeBitCast(sp, to: DeviceFn.self)
            let unreg   = unsafeBitCast(ur, to: RegisterFn.self)
            for d in devices { unreg(d, MultitouchRemote.contactCB); stopDev(d, 0) }
        }
        devices.removeAll()
        deviceList = nil                          // 放掉保活的数组
        running = false
        MultitouchRemote.hasPrev = false
        FileLog.write("🖐 遥控器触摸板已释放")
    }

    /// 接触帧回调：连续跟踪同一根手指的位移 → 平滑移动光标。
    /// 关键：用触点标识(identifier)区分手指，只有「同一根手指的连续帧」才算位移；
    /// 抬手时蹭到别处会是新标识 → 不移动；并忽略异常大跳 → 不跳变。
    private static let contactCB: MTContactCallback = { _, contacts, num, _, _ in
        guard num >= 1, let c = contacts else { hasPrev = false; return 0 }
        let st = c.load(fromByteOffset: 20, as: Int32.self)   // Finger.state
        // 只在 st=4(稳定持续按触) 时跟踪；落指(1/3)、悬停(2)、抬手/离开(5/6/7) 一律停 + 复位。
        // 实测跳变全发生在 st=5/6/7→1（抬手→新触）这些过渡；落指阶段接触面在变、质心漂移也会偏。
        guard st == 4 else { hasPrev = false; settle = 0; return 0 }
        let id = c.load(fromByteOffset: 16, as: Int32.self)   // Finger.identifier
        let x  = c.load(fromByteOffset: 32, as: Float.self)   // normalized.pos.x
        let y  = c.load(fromByteOffset: 36, as: Float.self)   // normalized.pos.y
        if hasPrev && id == prevID {
            if settle > 0 {
                settle -= 1                                    // 落指后头几帧让接触稳定，不移动 → 换位置再触不偏
            } else {
                let ndx = Double(x - prevX), ndy = Double(y - prevY)
                let mag = (ndx * ndx + ndy * ndy).squareRoot()
                if mag > MultitouchRemote.dead && mag < 0.12 {   // 死区滤手抖；上限滤残留大跳
                    let s = (mag - MultitouchRemote.dead) / mag  // 软死区：保方向，从阈值平滑起步
                    let cdx = ndx * s * gain, cdy = -ndy * s * gain      // 触摸 y 向上为正，屏幕 y 向下为正
                    moveCursor(dx: cdx, dy: cdy)
                    gestureAccum += (cdx * cdx + cdy * cdy).squareRoot()  // 累计本手势移动量
                    if gestureAccum > 25 { lastMoveAt = ProcessInfo.processInfo.systemUptime }  // 够大才算"指点"
                }
            }
        } else {
            settle = 3                                         // 新触/换指 → 进入稳定期
            gestureAccum = 0                                   // 新触点清零（按 OK 的微抖不会累成"指点"）
        }
        prevID = id; prevX = x; prevY = y; hasPrev = true
        return 0
    }

    private static func moveCursor(dx: Double, dy: Double) {
        let cur = CGEvent(source: nil)?.location ?? .zero
        let p = clamp(CGPoint(x: cur.x + dx, y: cur.y + dy))
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private static func clamp(_ p: CGPoint) -> CGPoint {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &n)
        var u = CGRect.null
        for i in 0..<Int(n) { u = u.union(CGDisplayBounds(ids[i])) }
        guard !u.isNull else { return p }
        return CGPoint(x: min(max(p.x, u.minX), u.maxX - 1), y: min(max(p.y, u.minY), u.maxY - 1))
    }
}
