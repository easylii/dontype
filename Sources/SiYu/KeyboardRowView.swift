import AppKit

/// 简化的「虚拟键盘」：画出 Mac 底部修饰键那一排键帽，点着选触发键、测试时对应键高亮闪一下。
/// 可点的键 = Trigger.all 的 5 个：fn / ⌃ control / ⌥ option / 右⌘ / 右⌥；空格、左⌘、方向键只作展示。
final class KeyboardRowView: NSView {
    private struct Key {
        let label: String       // 主符号
        let sub: String         // 小字名
        let triggerID: String?  // nil = 仅展示、不可点
        let weight: CGFloat     // 宽度权重
        var rect: NSRect = .zero
    }

    var onSelect: ((Trigger) -> Void)?
    var selectedID: String = "" { didSet { needsDisplay = true } }
    /// 当前选中功能的颜色（选中键满色显示）。
    var selectedColor: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
    /// 键 → (功能名, 颜色)：被某功能占用的键，浅色底 + 小字显示功能名。
    var badges: [String: (text: String, color: NSColor)] = [:] { didSet { needsDisplay = true } }
    private var flashingID: String?

    private var keys: [Key] = [
        Key(label: "fn", sub: "fn", triggerID: "fn", weight: 1),
        Key(label: "⌃", sub: "control", triggerID: "control", weight: 1),
        Key(label: "⌥", sub: "option", triggerID: "option", weight: 1),
        Key(label: "⌘", sub: "左 command", triggerID: "leftCommand", weight: 1.2),
        Key(label: "", sub: "space", triggerID: nil, weight: 3.4),
        Key(label: "⌘", sub: "右 command", triggerID: "rightCommand", weight: 1.2),
        Key(label: "⌥", sub: "右 option", triggerID: "rightOption", weight: 1),
        Key(label: "◂▾▸", sub: "", triggerID: nil, weight: 1),
    ]

    override var isFlipped: Bool { true }

    /// 按当前 bounds 算各键帽矩形（draw / mouseDown 前都调，免受 layout 时序影响）
    private func layoutKeys() {
        let totalWeight = keys.reduce(0) { $0 + $1.weight }
        let gap: CGFloat = 4
        let usable = bounds.width - gap * CGFloat(keys.count - 1)
        var x: CGFloat = 0
        for i in keys.indices {
            let w = usable * keys[i].weight / totalWeight
            keys[i].rect = NSRect(x: x, y: 0, width: w, height: bounds.height)
            x += w + gap
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        layoutKeys()
        for key in keys {
            let path = NSBezierPath(roundedRect: key.rect, xRadius: 6, yRadius: 6)
            let isSel = key.triggerID != nil && key.triggerID == selectedID
            let isFlash = key.triggerID != nil && key.triggerID == flashingID
            let badge = key.triggerID.flatMap { badges[$0] }
            let fill: NSColor
            if isFlash { fill = NSColor.systemGreen }
            else if isSel { fill = selectedColor }                          // 选中功能的键：满色
            else if let badge { fill = badge.color.withAlphaComponent(0.20) } // 被别的功能占用：浅色底
            else if key.triggerID == nil { fill = NSColor.windowBackgroundColor }
            else { fill = NSColor.controlBackgroundColor }
            fill.setFill(); path.fill()
            NSColor.separatorColor.setStroke(); path.lineWidth = 0.5; path.stroke()

            let lit = isSel || isFlash
            if !key.label.isEmpty {
                drawCentered(key.label, in: key.rect,
                             font: .systemFont(ofSize: 15, weight: .medium),
                             color: lit ? .white : (key.triggerID == nil ? .tertiaryLabelColor : .labelColor),
                             dy: -7)
            }
            // 小字：被占用 → 功能名（功能色）；否则 → 硬件名
            let sub = badge?.text ?? key.sub
            if !sub.isEmpty {
                let subColor: NSColor = lit ? .white
                    : (badge != nil ? badge!.color : (key.triggerID == nil ? .tertiaryLabelColor : .secondaryLabelColor))
                drawCentered(sub, in: key.rect, font: .systemFont(ofSize: 9, weight: badge != nil ? .semibold : .regular),
                             color: subColor, dy: 9)
            }
        }
    }

    private func drawCentered(_ s: String, in rect: NSRect, font: NSFont, color: NSColor, dy: CGFloat) {
        let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (s as NSString).size(withAttributes: attr)
        let p = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2 + dy)
        (s as NSString).draw(at: p, withAttributes: attr)
    }

    override func mouseDown(with event: NSEvent) {
        layoutKeys()
        let pt = convert(event.locationInWindow, from: nil)
        for key in keys {
            if let id = key.triggerID, key.rect.contains(pt) {
                selectedID = id
                onSelect?(Trigger.from(id))
                return
            }
        }
    }

    /// 测试检测到某键时闪绿 0.5s
    func flash(_ id: String) {
        flashingID = id
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.flashingID = nil
            self?.needsDisplay = true
        }
    }
}
