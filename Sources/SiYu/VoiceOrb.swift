import AppKit

/// 语音助手的极简状态球（不显示文字）：听=绿(随音量脉动) / 想=橙 / 说=蓝。点一下停止。
final class VoiceOrb {
    var onStop: (() -> Void)?
    private var panel: NSPanel?
    private var orb: OrbView?

    func show() {
        if panel == nil { build() }
        position()
        panel?.orderFrontRegardless()
    }
    func hide() { panel?.orderOut(nil) }

    func setState(_ s: VoiceLoop.State) { orb?.setState(s) }
    func setLevel(_ lv: Float) { orb?.setLevel(lv) }

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
