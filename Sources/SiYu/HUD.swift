import AppKit
import ApplicationServices

/// 带闭包回调的按钮，省去 target/action 样板。
final class ClosureButton: NSButton {
    private var handler: () -> Void = {}
    convenience init(title: String, handler: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.title = title
        self.bezelStyle = .rounded
        self.handler = handler
        self.target = self
        self.action = #selector(fire)
    }
    @objc private func fire() { handler() }
}

/// 实时声波：滚动柱状图，新电平从右侧进入、向左滚动。
final class WaveView: NSView {
    var barColor: NSColor = .white
    private var levels: [Float] = []
    private let barW: CGFloat = 3
    private let gap: CGFloat = 3

    private var barCount: Int { max(1, Int(bounds.width / (barW + gap))) }

    func push(_ level: Float) {
        levels.append(level)
        if levels.count > barCount { levels.removeFirst(levels.count - barCount) }
        needsDisplay = true
    }

    func reset() {
        levels.removeAll()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let midY = bounds.midY
        let maxH = bounds.height - 4
        barColor.setFill()
        // 还没有电平时画一排待机圆点
        if levels.isEmpty {
            var x = bounds.width - (barW + gap)
            while x >= 0 {
                NSBezierPath(ovalIn: NSRect(x: x, y: midY - barW / 2, width: barW, height: barW)).fill()
                x -= barW + gap
            }
            return
        }
        for (i, lv) in levels.enumerated() {
            let x = bounds.width - CGFloat(levels.count - i) * (barW + gap)
            if x < 0 { continue }
            let h = max(barW, CGFloat(lv) * maxH)
            let r = NSRect(x: x, y: midY - h / 2, width: barW, height: h)
            NSBezierPath(roundedRect: r, xRadius: barW / 2, yRadius: barW / 2).fill()
        }
    }
}

/// 菜单栏图标下方的黑色小药丸（固定 70×36），纯图形化：
/// 录音=图标+声波 → 整理中=图标+转圈 → 结果=图标+✓（旁边再浮一个独立的圆形 copy 药丸）→ 错误=图标+✗。
final class HUD: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var wave: WaveView!
    private var label: NSTextField!            // 单字符状态（✓/✗），详情挂 toolTip
    private var spinner: NSProgressIndicator!
    private var micIconView: NSImageView!

    private var copyPanel: NSPanel?            // 结果时旁边独立的圆形 copy 药丸
    private var hideTimer: Timer?
    private var speakWaveTimer: Timer?         // 朗读时驱动合成声波

    /// 药丸位置 = 「当前屏顶部中点」+ 这个偏移。拖动后记住、跨屏跟随、下次复用。
    private var offset = CGPoint.zero
    private var programmaticMove = false       // 区分「我们摆位」和「用户拖动」
    private var saveTimer: Timer?
    /// 偏移变化时回调（AppDelegate 持久化到 config）
    var onOffsetChanged: ((CGPoint) -> Void)?
    /// 启动时从 config 恢复上次的偏移
    func setSavedOffset(_ p: CGPoint) { offset = p }
    private var fullText = ""

    private let pillW: CGFloat = 70
    private let pillH: CGFloat = 36
    private let copyD: CGFloat = 36            // copy 药丸直径
    private let copyGap: CGFloat = 8           // 主药丸与 copy 药丸间距

    // MARK: 状态

    func showRecording(under anchor: NSRect?, micKind: MicSourceKind) {
        cancelTimer()
        if panel == nil { build() }
        copyPanel?.orderOut(nil)
        micIconView.image = MicIcon.image(for: micKind)
        wave.reset()
        setVisible(wave: true)
        position(under: anchor)
        panel?.orderFrontRegardless()
    }

    func updateLevel(_ level: Float) {
        guard panel?.isVisible == true, !wave.isHidden else { return }
        wave.push(level)
    }

    func showProcessing() {
        cancelTimer()
        guard panel != nil else { return }
        copyPanel?.orderOut(nil)
        setVisible(spinner: true)
        spinner.startAnimation(nil)
    }

    /// 结果：主药丸显示 ✓（已粘贴/已识别），旁边浮出独立圆形 copy 药丸（悬停预览全文）
    func showResult(_ text: String, pasted: Bool) {
        guard panel != nil else { return }
        fullText = text
        label.textColor = NSColor.systemGreen.blended(withFraction: 0.25, of: .white) ?? .systemGreen
        label.stringValue = "✓"
        setVisible(label: true)
        showCopyPill(tooltip: text)
        scheduleHide(after: 8)
    }

    func showError(_ msg: String, micOff: Bool = false, under anchor: NSRect? = nil) {
        if panel == nil { build() }
        copyPanel?.orderOut(nil)
        micIconView.image = MicIcon.image(for: micOff ? .off : .builtin)
        if micOff {
            position(under: anchor)
            panel?.orderFrontRegardless()
        }
        label.textColor = NSColor.systemRed.blended(withFraction: 0.3, of: .white) ?? .systemRed
        label.stringValue = "✗"
        setVisible(label: true)
        label.toolTip = msg
        scheduleHide(after: 4)
    }

    /// 朗读中：左侧喇叭/暂停图标 + 声波（朗读时滚动、暂停时静止），常驻到收起（stop/读完）
    func showSpeaking(paused: Bool, under anchor: NSRect?) {
        cancelTimer()            // 内部会停掉旧的朗读声波 timer
        if panel == nil { build() }
        copyPanel?.orderOut(nil)
        let sym = paused ? "pause.fill" : "speaker.wave.2.fill"
        micIconView.image = NSImage(systemSymbolName: sym, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
        micIconView.contentTintColor = .white
        setVisible(wave: true)
        position(under: anchor)
        panel?.orderFrontRegardless()
        if !paused { startSpeakWave() }   // 暂停则保持当前静止波形
    }

    /// 朗读没有真实麦克风电平，用一个有起伏的合成波形表示「正在说」
    private func startSpeakWave() {
        speakWaveTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
            self?.wave.push(Float.random(in: 0.12...0.85))
        }
    }

    private func stopSpeakWave() {
        speakWaveTimer?.invalidate()
        speakWaveTimer = nil
    }

    /// 短暂提示（如「没有选中文字」）：显示静音图标 + tooltip，2s 后消失
    func flash(_ message: String, under anchor: NSRect?) {
        cancelTimer()
        if panel == nil { build() }
        copyPanel?.orderOut(nil)
        micIconView.image = NSImage(systemSymbolName: "speaker.slash.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
        micIconView.contentTintColor = .white
        setVisible()
        panel?.contentView?.toolTip = message
        position(under: anchor)
        panel?.orderFrontRegardless()
        scheduleHide(after: 2)
    }

    func hide() {
        cancelTimer()
        copyPanel?.orderOut(nil)
        panel?.orderOut(nil)
    }

    // MARK: 内部

    private func setVisible(wave w: Bool = false, spinner s: Bool = false, label l: Bool = false) {
        wave.isHidden = !w
        label.isHidden = !l
        if !s { spinner.stopAnimation(nil) }
        spinner.isHidden = !s
    }

    private func copyTapped() {
        Paster.copy(fullText)
        hide()
    }

    /// 紧贴主药丸右侧浮出 copy 药丸（主药丸已定位好）
    private func showCopyPill(tooltip: String) {
        guard let main = panel else { return }
        if copyPanel == nil { buildCopyPill() }
        guard let c = copyPanel else { return }
        c.contentView?.toolTip = tooltip
        let mf = main.frame
        var x = mf.maxX + copyGap
        let y = mf.midY - copyD / 2
        // 右侧空间不够（贴右边缘）就改放主药丸左侧；以主药丸所在屏为准
        if let screen = main.screen, x + copyD > screen.frame.maxX - 8 {
            x = mf.minX - copyGap - copyD
        }
        c.setFrameOrigin(NSPoint(x: x, y: y))
        c.orderFrontRegardless()
    }

    private func scheduleHide(after sec: TimeInterval) {
        cancelTimer()
        hideTimer = Timer.scheduledTimer(withTimeInterval: sec, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    private func cancelTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
        stopSpeakWave()   // 离开朗读态/任何状态切换都停掉合成声波（showSpeaking 会再启）
    }

    private func position(under anchor: NSRect?) {
        guard let p = panel else { return }
        let screen = activeScreen()
        let f = screen.frame
        // 基准 = 当前屏顶部中点（多屏/单屏都贴你正在打字那块屏的最顶）；再叠加用户拖动的偏移
        let baseX = f.midX - p.frame.width / 2
        let baseY = f.maxY - p.frame.height - 6
        var x = baseX + offset.x
        var y = baseY + offset.y
        // 夹住在屏内，换了屏/分辨率也不会跑到看不见的地方
        x = min(max(f.minX + 8, x), f.maxX - p.frame.width - 8)
        y = min(max(f.minY + 8, y), f.maxY - p.frame.height - 6)
        programmaticMove = true
        p.setFrameOrigin(NSPoint(x: x, y: y))
        programmaticMove = false
    }

    /// 当前屏顶部中点（用于把绝对坐标换算成「相对顶部」的偏移）
    private func topCenterBase(_ screen: NSScreen) -> NSPoint {
        guard let p = panel else { return .zero }
        return NSPoint(x: screen.frame.midX - p.frame.width / 2,
                       y: screen.frame.maxY - p.frame.height - 6)
    }

    // 用户拖动药丸：换算成相对当前屏顶部的偏移并记住（防抖后持久化）
    func windowDidMove(_ notification: Notification) {
        guard !programmaticMove, let p = panel else { return }
        let screen = p.screen ?? activeScreen()
        let base = topCenterBase(screen)
        offset = CGPoint(x: p.frame.origin.x - base.x, y: p.frame.origin.y - base.y)
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.onOffsetChanged?(self.offset)
        }
    }

    /// 文字将要落到的那一页/屏：优先「键盘焦点窗口」所在屏（=光标处），
    /// 取不到再退到鼠标所在屏，最后主屏。解决分屏/多屏时胶囊跑到别的屏看不见。
    private func activeScreen() -> NSScreen {
        if let s = focusedWindowScreen() { return s }
        let mouse = NSEvent.mouseLocation
        if let s = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) { return s }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    /// 用辅助功能 API 拿前台 App 焦点窗口的几何，换算出它在哪块屏
    private func focusedWindowScreen() -> NSScreen? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let winRef else { return nil }
        let win = winRef as! AXUIElement
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        // AX 是顶左原点、Y 向下、全局坐标；换成 Cocoa（底左原点）再找屏幕
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let center = CGPoint(x: pos.x + size.width / 2, y: primaryH - (pos.y + size.height / 2))
        return NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) }
    }

    /// 浮动药丸通用样式（圆角黑底、置于全屏层之上）
    private func makeFloatingPanel(w: CGFloat, h: CGFloat) -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .screenSaver
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return p
    }

    /// 独立的圆形 copy 药丸：整块就是一个按钮，点一下复制全文并收起
    private func buildCopyPill() {
        let p = makeFloatingPanel(w: copyD, h: copyD)
        let btn = ClosureButton(title: "") { [weak self] in self?.copyTapped() }
        btn.isBordered = false
        btn.wantsLayer = true
        btn.frame = NSRect(x: 0, y: 0, width: copyD, height: copyD)
        btn.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.88).cgColor
        btn.layer?.cornerRadius = copyD / 2
        if let img = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制")?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .semibold)) {
            btn.image = img
            btn.contentTintColor = .white
        } else {
            btn.attributedTitle = NSAttributedString(
                string: "⧉",
                attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 16, weight: .bold)]
            )
        }
        btn.toolTip = "复制全文"
        p.contentView = btn
        copyPanel = p
    }

    private func build() {
        let p = makeFloatingPanel(w: pillW, h: pillH)
        p.isMovableByWindowBackground = true   // 拖背景即可移动
        p.delegate = self                      // 监听拖动以记住位置

        let bg = NSView()
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.88).cgColor
        bg.layer?.cornerRadius = pillH / 2
        p.contentView = bg

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyUpOrDown

        let w = WaveView()
        w.translatesAutoresizingMaskIntoConstraints = false

        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: 16, weight: .bold)
        l.alignment = .center
        l.isHidden = true
        l.translatesAutoresizingMaskIntoConstraints = false

        let sp = NSProgressIndicator()
        sp.style = .spinning
        sp.controlSize = .small
        sp.isHidden = true
        sp.appearance = NSAppearance(named: .darkAqua)   // 黑底上转白圈
        sp.translatesAutoresizingMaskIntoConstraints = false

        bg.addSubview(icon)
        bg.addSubview(w)
        bg.addSubview(l)
        bg.addSubview(sp)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            w.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            w.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -10),
            w.topAnchor.constraint(equalTo: bg.topAnchor, constant: 6),
            w.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -6),

            // ✓/✗ 居中在声波区域
            l.centerXAnchor.constraint(equalTo: w.centerXAnchor),
            l.centerYAnchor.constraint(equalTo: bg.centerYAnchor),

            sp.centerXAnchor.constraint(equalTo: w.centerXAnchor),
            sp.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
            sp.widthAnchor.constraint(equalToConstant: 16),
            sp.heightAnchor.constraint(equalToConstant: 16),
        ])

        self.panel = p
        self.wave = w
        self.label = l
        self.spinner = sp
        self.micIconView = icon
    }
}
