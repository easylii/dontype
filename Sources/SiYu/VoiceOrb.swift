import AppKit

/// 语音助手的极简状态球（不显示文字）：听=绿(随音量脉动) / 想=橙 / 说=蓝。点一下停止。
final class VoiceOrb {
    var onStop: (() -> Void)?
    private var panel: NSPanel?
    private var orb: OrbView?
    private var bubblePanel: NSPanel?
    private var bubbleBG: ThoughtBubbleView?
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

    /// 思考泡泡：球的右上方，大字、最多 3 行自动换行，左下角带「在想」拖尾两小圆，向上飘 + 渐隐约 2.4s（复用面板）。
    func bubble(_ text: String) {
        if bubblePanel == nil { buildBubble() }
        guard let bp = bubblePanel, let bg = bubbleBG, let lab = bubbleLabel, let orbP = panel else { return }
        lab.stringValue = text

        let padX: CGFloat = 11, padY: CGFloat = 7
        let maxTextW: CGFloat = 180                                  // 到这就换行
        let singleW = ceil((text as NSString).size(withAttributes: [.font: lab.font as Any]).width) + 1
        let textW = max(28, min(singleW, maxTextW))                 // 跟文字一样宽，短就窄
        let bound = (text as NSString).boundingRect(
            with: NSSize(width: textW, height: 200),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: lab.font as Any])
        let textH = min(ceil(bound.height), lineHeightCap)          // 封顶 3 行
        let pillW = textW + padX * 2
        let pillH = max(textH + padY * 2, 28)

        // 主体周围留边；左下角留出拖尾小圆的空间
        let leftPad: CGFloat = 12, rightPad: CGFloat = 12, topPad: CGFloat = 12, tailPad: CGFloat = 22
        let panelW = leftPad + pillW + rightPad, panelH = tailPad + pillH + topPad
        bp.setContentSize(NSSize(width: panelW, height: panelH))

        let body = NSRect(x: leftPad, y: tailPad, width: pillW, height: pillH)
        bg.frame = NSRect(x: 0, y: 0, width: panelW, height: panelH)
        bg.bodyRect = body
        lab.frame = NSRect(x: body.minX + padX, y: body.minY + padY, width: textW, height: textH)

        // 位置：球的右上方
        let bodyCenterX = orbP.frame.midX + 100
        let startX = bodyCenterX - (leftPad + pillW / 2)
        let startY = orbP.frame.midY + 6
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

    /// 3 行文字的高度上限（按泡泡字号估算）。
    private var lineHeightCap: CGFloat { ceil((NSFont.systemFont(ofSize: 12.5, weight: .medium).boundingRectForFont.height) * 3) + 6 }

    private func buildBubble() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 130),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.isFloatingPanel = true; p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let bg = ThoughtBubbleView(frame: NSRect(x: 0, y: 0, width: 280, height: 130))
        let lab = NSTextField(wrappingLabelWithString: "")
        lab.font = .systemFont(ofSize: 12.5, weight: .medium)
        lab.textColor = .white; lab.alignment = .center
        lab.maximumNumberOfLines = 3
        lab.isBezeled = false; lab.isEditable = false; lab.drawsBackground = false
        bg.addSubview(lab)
        p.contentView = bg
        bubblePanel = p; bubbleBG = bg; bubbleLabel = lab
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

/// 思考泡泡：圆角主体 + 左下角两个递减小圆（「在想」拖尾，朝状态球方向），半透明深色。
final class ThoughtBubbleView: NSView {
    var bodyRect: NSRect = .zero { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        guard bodyRect.width > 0 else { return }
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: bodyRect, xRadius: 12, yRadius: 12).fill()
        // 左下角拖尾两小圆（y 向下、x 向左 = 朝球）
        NSBezierPath(ovalIn: NSRect(x: bodyRect.minX + 3, y: bodyRect.minY - 9,  width: 9, height: 9)).fill()
        NSBezierPath(ovalIn: NSRect(x: bodyRect.minX - 5, y: bodyRect.minY - 18, width: 5, height: 5)).fill()
    }
}
