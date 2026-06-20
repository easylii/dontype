import AppKit
import GameController
import CoreGraphics

/// 蓝牙游戏手柄输入（macOS 原生 GameController 框架，标准 Xbox/PS/8BitDo 手柄即插即用，不依赖第三方）。
/// 映射：A 键 → 切换听写；左摇杆 → 移动鼠标光标；十字键 → 方向键；B 键 → 鼠标左键点击。
/// 用途：隔着房间用手柄当遥控（Apple TV 遥控器只能传媒体键，给不了光标/方向键 —— 那部分由手柄补齐）。
final class GameControllerInput {
    /// A 键按下：切换听写（开始/结束由上层按当前状态决定）—— 主线程
    var onToggleDictation: (() -> Void)?

    private weak var pad: GCExtendedGamepad?
    private var pollTimer: Timer?
    private let src = CGEventSource(stateID: .hidSystemState)

    func start() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(connected(_:)), name: .GCControllerDidConnect, object: nil)
        nc.addObserver(self, selector: #selector(disconnected(_:)), name: .GCControllerDidDisconnect, object: nil)
        GCController.controllers().forEach { attach($0) }
        GCController.startWirelessControllerDiscovery {}
    }

    @objc private func connected(_ n: Notification) {
        if let c = n.object as? GCController { attach(c) }
    }

    @objc private func disconnected(_ n: Notification) {
        if let c = n.object as? GCController, c.extendedGamepad === pad {
            pad = nil
            stopPolling()
            FileLog.write("🎮 手柄已断开")
        }
    }

    private func attach(_ c: GCController) {
        guard let gp = c.extendedGamepad else { return }
        pad = gp
        FileLog.write("🎮 手柄已连接：\(c.vendorName ?? "Controller")")

        // A 键：切换听写（只在按下时触发一次）
        gp.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            DispatchQueue.main.async { self?.onToggleDictation?() }
        }
        // B 键：鼠标左键按下/抬起（可点选、可拖拽）
        gp.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.mouseButton(down: pressed)
        }
        // 十字键 → 方向键（按下发 keyDown、抬起发 keyUp）
        gp.dpad.up.pressedChangedHandler    = { [weak self] _, _, p in self?.arrow(126, p) }
        gp.dpad.down.pressedChangedHandler  = { [weak self] _, _, p in self?.arrow(125, p) }
        gp.dpad.left.pressedChangedHandler  = { [weak self] _, _, p in self?.arrow(123, p) }
        gp.dpad.right.pressedChangedHandler = { [weak self] _, _, p in self?.arrow(124, p) }

        startPolling()
    }

    // MARK: 左摇杆移动光标（60Hz 轮询）

    private func startPolling() {
        stopPolling()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func tick() {
        guard let gp = pad else { return }
        let x = Double(gp.leftThumbstick.xAxis.value)
        let y = Double(gp.leftThumbstick.yAxis.value)
        let dead = 0.12
        if abs(x) < dead && abs(y) < dead { return }
        let speed = 18.0                         // 满偏时每帧最大像素
        let dx = x * abs(x) * speed              // 平方缓动：小偏移微调、大偏移快移
        let dy = -y * abs(y) * speed             // 手柄 y 向上为正，屏幕 y 向下为正
        moveCursor(dx: dx, dy: dy)
    }

    private func moveCursor(dx: Double, dy: Double) {
        let cur = CGEvent(source: nil)?.location ?? .zero
        let p = clampToScreens(CGPoint(x: cur.x + dx, y: cur.y + dy))
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    /// 把目标点夹在所有显示器并集范围内（支持多屏）。
    private func clampToScreens(_ p: CGPoint) -> CGPoint {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        var union = CGRect.null
        for i in 0..<Int(count) { union = union.union(CGDisplayBounds(ids[i])) }
        guard !union.isNull else { return p }
        return CGPoint(x: min(max(p.x, union.minX), union.maxX - 1),
                       y: min(max(p.y, union.minY), union.maxY - 1))
    }

    // MARK: 点击 / 方向键

    private func mouseButton(down: Bool) {
        let p = CGEvent(source: nil)?.location ?? .zero
        CGEvent(mouseEventSource: src, mouseType: down ? .leftMouseDown : .leftMouseUp,
                mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private func arrow(_ key: CGKeyCode, _ pressed: Bool) {
        CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: pressed)?.post(tap: .cghidEventTap)
    }
}
