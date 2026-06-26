import AppKit

/// 统一热键面板：一张键盘搞定三个功能（听写 / 朗读 / 语音助手）。
/// 先点上方功能芯片选中它，再点键盘上的键给它换键；键盘上每个被占用的键显示功能名 + 颜色。
/// 点到别的功能占着的键 → 两功能自动对调（保证三者各有一个键、互不冲突）。改了即时持久化 + 重绑。
final class HotkeyCenter: NSObject, NSWindowDelegate {
    /// 一个可分配热键的功能：名字 / 手势说明 / 颜色 / 取当前键 / 应用新键（持久化 + 重绑）。
    struct Fn {
        let name: String
        let gesture: String
        let color: NSColor
        let get: () -> String
        let apply: (String) -> Void
    }

    private let fns: [Fn]
    init(_ fns: [Fn]) { self.fns = fns }

    private var window: NSWindow?
    private var keyboard: KeyboardRowView!
    private var chips: [NSButton] = []
    private var gestureLabel: NSTextField!
    private var armed = 0   // 当前选中的功能 index

    func show() {
        if window == nil { build() }
        armed = 0
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.center(); window?.makeKeyAndOrderFront(nil)
    }

    /// 芯片高亮当前功能 + 键盘按当前映射打角标、选中功能的键满色。
    private func refresh() {
        for (i, chip) in chips.enumerated() {
            chip.title = "\(fns[i].name)：\(Trigger.from(fns[i].get()).label)"
            chip.contentTintColor = fns[i].color
            chip.state = (i == armed) ? .on : .off
        }
        var badges = [String: (text: String, color: NSColor)]()
        for f in fns { badges[f.get()] = (f.name, f.color) }
        keyboard.badges = badges
        keyboard.selectedID = fns[armed].get()
        keyboard.selectedColor = fns[armed].color
        gestureLabel.stringValue = "• " + fns[armed].gesture
    }

    @objc private func chipTapped(_ sender: NSButton) {
        armed = sender.tag
        refresh()
    }

    /// 把键分配给当前选中功能；若该键被别的功能占用 → 两功能对调。
    private func assign(_ keyID: String) {
        let me = armed
        let myOld = fns[me].get()
        guard keyID != myOld else { return }
        if let other = fns.indices.first(where: { $0 != me && fns[$0].get() == keyID }) {
            fns[other].apply(myOld)        // 占用者拿我的旧键（对调）
        }
        fns[me].apply(keyID)
        keyboard.flash(keyID)
        refresh()
    }

    @objc private func close() { window?.close() }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 240),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L.t(zh: "丝语 · 热键", en: "Dontype · Hotkeys")
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.delegate = self

        let root = NSStackView()
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: L.t(zh: "热键 · 一张键盘搞定", en: "Hotkeys · one keyboard"))
        title.font = .boldSystemFont(ofSize: 15)
        let desc = NSTextField(labelWithString:
            L.t(zh: "先点一个功能选中它，再点下面键盘上的键给它换键。占到别的功能的键会自动对调。",
                en: "Pick a function, then click a key below to assign it. Taking another's key swaps them."))
        desc.font = .systemFont(ofSize: 12); desc.textColor = .secondaryLabelColor
        desc.lineBreakMode = .byWordWrapping; desc.preferredMaxLayoutWidth = 412

        let chipRow = NSStackView(); chipRow.orientation = .horizontal; chipRow.spacing = 8
        for (i, f) in fns.enumerated() {
            let b = NSButton(title: f.name, target: self, action: #selector(chipTapped(_:)))
            b.tag = i; b.setButtonType(.pushOnPushOff); b.bezelStyle = .rounded
            b.contentTintColor = f.color
            chips.append(b); chipRow.addArrangedSubview(b)
        }

        keyboard = KeyboardRowView()
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        keyboard.widthAnchor.constraint(equalToConstant: 412).isActive = true
        keyboard.heightAnchor.constraint(equalToConstant: 56).isActive = true
        keyboard.onSelect = { [weak self] t in self?.assign(t.id) }

        gestureLabel = NSTextField(labelWithString: "…")
        gestureLabel.font = .systemFont(ofSize: 12); gestureLabel.textColor = .secondaryLabelColor
        gestureLabel.lineBreakMode = .byWordWrapping; gestureLabel.preferredMaxLayoutWidth = 412

        let done = NSButton(title: L.t(zh: "完成", en: "Done"), target: self, action: #selector(close))
        done.bezelStyle = .rounded; done.keyEquivalent = "\r"
        let footer = NSStackView(views: [NSView(), done]); footer.orientation = .horizontal
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.widthAnchor.constraint(equalToConstant: 412).isActive = true

        [title, desc, chipRow, keyboard, gestureLabel, footer].forEach { root.addArrangedSubview($0) }

        let content = NSView(); content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        w.contentView = content
        w.setContentSize(NSSize(width: 460, height: content.fittingSize.height))
        window = w
    }
}
