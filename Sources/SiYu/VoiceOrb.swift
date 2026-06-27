import AppKit

/// 语音助手的极简状态球（不显示文字）：听=绿(随音量脉动) / 想=橙 / 说=蓝。点一下停止。
final class VoiceOrb {
    var onStop: (() -> Void)?
    private var panel: NSPanel?
    private var orb: OrbView?
    private var bubblePanel: NSPanel?
    private var bubbleLabel: NSTextField?
    private var bubbleSeq = 0

    func show() {
        if panel == nil { build() }
        position()
        panel?.orderFrontRegardless()
    }
    func hide() { panel?.orderOut(nil); bubblePanel?.orderOut(nil) }

    func setState(_ s: VoiceLoop.State) {
        orb?.setState(s)
        switch s {                                  // 状态变化时弹个半透明泡泡（让你在它没出声时也知道在干嘛）
        case .listening: bubble(L.t(zh: "在听你说…", en: "Listening…"))
        case .thinking:  bubble(L.t(zh: "在想…",   en: "Thinking…"))
        case .speaking:  bubble(L.t(zh: "在说…",   en: "Speaking…"))
        case .idle:      break
        }
    }
    func setLevel(_ lv: Float) { orb?.setLevel(lv) }

    /// 半透明状态泡泡：出现在球上方，向上飘一小段 + 渐隐，约 2.4s 自动消失（复用同一个面板）。
    func bubble(_ text: String) {
        if bubblePanel == nil { buildBubble() }
        guard let bp = bubblePanel, let lab = bubbleLabel, let orbP = panel else { return }
        lab.stringValue = "  \(text)  "
        let startX = orbP.frame.midX - bp.frame.width / 2
        let startY = orbP.frame.midY + 46
        bp.setFrameOrigin(NSPoint(x: startX, y: startY))
        bp.alphaValue = 0.95
        bp.orderFrontRegardless()
        bubbleSeq += 1
        let seq = bubbleSeq
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 2.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            bp.animator().setFrameOrigin(NSPoint(x: startX, y: startY + 46))
            bp.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            if self?.bubbleSeq == seq { self?.bubblePanel?.orderOut(nil) }   // 只让最新那次收尾隐藏
        })
    }

    private func buildBubble() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 180, height: 30),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.isFloatingPanel = true; p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 30))
        let lab = NSTextField(labelWithString: "")
        lab.font = .systemFont(ofSize: 12, weight: .medium)
        lab.textColor = .white; lab.alignment = .center
        lab.isBezeled = false; lab.isEditable = false; lab.drawsBackground = false
        lab.wantsLayer = true
        lab.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        lab.layer?.cornerRadius = 12; lab.layer?.masksToBounds = true
        lab.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(lab)
        NSLayoutConstraint.activate([
            lab.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            lab.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            lab.heightAnchor.constraint(equalToConstant: 24),
        ])
        p.contentView = host
        bubblePanel = p; bubbleLabel = lab
    }

    private func build() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 140, height: 140),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.isFloatingPanel = true; p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let v = OrbView(frame: NSRect(x: 0, y: 0, width: 140, height: 140))
        v.onClick = { [weak self] in self?.onStop?() }
        p.contentView = v
        panel = p; orb = v
    }

    private func position() {
        guard let p = panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let f = screen?.visibleFrame else { return }
        p.setFrameOrigin(NSPoint(x: f.midX - 70, y: f.minY + 56))   // 底部居中偏上
    }
}

/// 球本体：画一个随状态变色/脉动的圆 + 中心状态图标。
final class OrbView: NSView {
    var onClick: (() -> Void)?
    private var state: VoiceLoop.State = .idle
    private var level: CGFloat = 0
    private var phase: CGFloat = 0
    private var timer: Timer?
    private let icon = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
        ])
        applyIcon()
    }
    required init?(coder: NSCoder) { fatalError() }

    func setState(_ s: VoiceLoop.State) {
        state = s; applyIcon()
        if s == .idle { timer?.invalidate(); timer = nil }
        else if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                self?.phase += 0.06; self?.needsDisplay = true
            }
        }
        needsDisplay = true
    }
    func setLevel(_ lv: Float) {
        level = CGFloat(min(1, max(0, lv)))
        if state == .listening { needsDisplay = true }
    }

    private func applyIcon() {
        let sym: String
        switch state {
        case .idle:      sym = "mic"          // 待命：灰色话筒，按右侧键开始说
        case .listening: sym = "mic.fill"
        case .thinking:  sym = "ellipsis"
        case .speaking:  sym = "speaker.wave.2.fill"
        }
        icon.image = NSImage(systemSymbolName: sym, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .bold))
    }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        let cx = bounds.midX, cy = bounds.midY
        let baseR: CGFloat = 30
        let color: NSColor
        var r = baseR
        switch state {
        case .idle:      color = .systemGray;   r = baseR
        case .listening: color = .systemGreen;  r = baseR + level * 22 + sin(phase * 2) * 1.5
        case .thinking:  color = .systemOrange; r = baseR + sin(phase) * 4
        case .speaking:  color = .systemBlue;   r = baseR + abs(sin(phase * 1.5)) * 7
        }
        color.withAlphaComponent(0.16).setFill()
        let ro = r + 12
        NSBezierPath(ovalIn: NSRect(x: cx - ro, y: cy - ro, width: ro * 2, height: ro * 2)).fill()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)).fill()
    }
}
