import AppKit

/// 朗读设置（从设置向导「⑦ 朗读选中文字」进入）：语音 / 语速 / 触发键 / 试听，改了即时生效并保存。
/// 触发键改动时把 readHotkey 切到候选键 + testMode（双击只给反馈、不真的开始朗读）；关窗退出 testMode。
final class ReadSetup: NSObject, NSWindowDelegate {
    private let readHotkey: HotkeyMonitor
    private let speaker: Speaker
    private let persist: ([String: Any]) -> Void

    init(readHotkey: HotkeyMonitor, speaker: Speaker, persist: @escaping ([String: Any]) -> Void) {
        self.readHotkey = readHotkey
        self.speaker = speaker
        self.persist = persist
    }

    private var window: NSWindow?
    private var voicePopup: NSPopUpButton!
    private var langPopup: NSPopUpButton!
    private var speedPopup: NSPopUpButton!
    private var keyboard: KeyboardRowView!
    private var keyStatus: NSTextField!
    private var voiceIDs: [String] = []        // 与 voicePopup 各项一一对应（"" = 自动）
    private let langCodes = ["auto", "zh", "en", "ja", "ko", "es", "fr"]
    private let speeds: [Double] = [0.4, 0.5, 0.6, 0.7]

    func show() {
        if window == nil { build() }
        loadFromConfig()
        beginKeyTest()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func loadFromConfig() {
        let c = Config.load()
        if let i = voiceIDs.firstIndex(of: c.readVoice) { voicePopup.selectItem(at: i) } else { voicePopup.selectItem(at: 0) }
        if let i = langCodes.firstIndex(of: c.readLang) { langPopup.selectItem(at: i) } else { langPopup.selectItem(at: 0) }
        if let i = speeds.firstIndex(where: { abs($0 - c.readRate) < 0.001 }) { speedPopup.selectItem(at: i) }
        keyboard.selectedID = c.readKey
    }

    // MARK: 动作（改了即时保存）

    @objc private func voiceChanged() { persist(["readVoice": voiceIDs[voicePopup.indexOfSelectedItem]]) }

    @objc private func langChanged() { persist(["readLang": langCodes[langPopup.indexOfSelectedItem]]) }

    @objc private func speedChanged() { persist(["readRate": speeds[speedPopup.indexOfSelectedItem]]) }

    private func keyChanged(_ t: Trigger) {
        persist(["readKey": t.id])
        readHotkey.setTrigger(t)
        keyboard.selectedID = t.id
        beginKeyTest()
    }

    @objc private func preview() {
        let c = Config.load()
        speaker.speak(L.t(zh: "这是朗读试听，包含 a little English。你好，世界。",
                          en: "This is a voice preview, 含一点中文。Hello, world."),
                      voiceID: c.readVoice, lang: c.readLang, rate: c.readRate)
    }

    @objc private func openVoiceSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func done() { window?.close() }

    /// 触发键测试态：双击候选键只回调反馈、不真的开始朗读；关窗时退出。
    private func beginKeyTest() {
        readHotkey.testMode = true
        readHotkey.onTestDoubleTap = { [weak self] in
            guard let self else { return }
            self.keyboard.flash(self.keyboard.selectedID)
            self.keyStatus.stringValue = "✓ " + L.t(zh: "检测到双击，可用", en: "Double-tap detected — works")
            self.keyStatus.textColor = .systemGreen
        }
        let label = Trigger.from(keyboard.selectedID).label
        keyStatus.stringValue = "• " + L.t(zh: "双击 \(label) 试试（测试时不会真的开始读）",
                                           en: "Double-tap \(label) to test (won't actually read)")
        keyStatus.textColor = .secondaryLabelColor
    }

    func windowWillClose(_ notification: Notification) {
        readHotkey.testMode = false
        readHotkey.onTestDoubleTap = nil
    }

    // MARK: UI

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L.t(zh: "丝语 · 朗读设置", en: "Dontype · Read-aloud Settings")
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.delegate = self

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: L.t(zh: "朗读选中文字", en: "Read selection aloud"))
        title.font = .boldSystemFont(ofSize: 15)
        let desc = NSTextField(labelWithString:
            L.t(zh: "选中（或把光标放到起点）→ 双击触发键，从这里往下读；单击暂停/继续，Esc 停。",
                en: "Select (or place cursor) → double-tap to read onward; tap to pause, Esc to stop."))
        desc.font = .systemFont(ofSize: 12); desc.textColor = .secondaryLabelColor
        desc.lineBreakMode = .byWordWrapping; desc.preferredMaxLayoutWidth = 412
        root.addArrangedSubview(title)
        root.addArrangedSubview(desc)

        // 语音
        voicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        voicePopup.target = self; voicePopup.action = #selector(voiceChanged)
        voiceIDs = [""]
        voicePopup.addItem(withTitle: L.t(zh: "自动（按文字语言挑）", en: "Automatic (by text language)"))
        let voices = Speaker.premiumVoices()
        for v in voices { voicePopup.addItem(withTitle: Speaker.display(v)); voiceIDs.append(v.identifier) }
        root.addArrangedSubview(labeledRow(L.t(zh: "语音", en: "Voice"), voicePopup))
        if voices.isEmpty {
            let dl = NSButton(title: L.t(zh: "没有 Premium 语音？去系统设置下载…", en: "No Premium voice? Download in Settings…"),
                              target: self, action: #selector(openVoiceSettings))
            dl.bezelStyle = .inline; dl.isBordered = false; dl.contentTintColor = .linkColor
            root.addArrangedSubview(dl)
        }

        // 主要语言：设了非自动 → 该语言在文中占比够就整篇用它读，避免被穿插的外语带偏
        langPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        langPopup.target = self; langPopup.action = #selector(langChanged)
        langPopup.addItems(withTitles: [
            L.t(zh: "自动（按内容判断）", en: "Automatic (by content)"),
            "中文", "English", "日本語", "한국어", "Español", "Français",
        ])
        root.addArrangedSubview(labeledRow(L.t(zh: "主要语言", en: "Primary"), langPopup))

        // 语速
        speedPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        speedPopup.target = self; speedPopup.action = #selector(speedChanged)
        speedPopup.addItems(withTitles: [L.t(zh: "慢", en: "Slow"), L.t(zh: "正常", en: "Normal"),
                                         L.t(zh: "快", en: "Fast"), L.t(zh: "更快", en: "Faster")])
        let preview = NSButton(title: L.t(zh: "试听", en: "Preview"), target: self, action: #selector(self.preview))
        preview.bezelStyle = .rounded
        let speedRow = labeledRow(L.t(zh: "语速", en: "Speed"), speedPopup)
        speedRow.addArrangedSubview(preview)
        root.addArrangedSubview(speedRow)

        // 触发键：虚拟键盘点选 + 双击测试反馈
        let keyLabel = NSTextField(labelWithString: L.t(zh: "触发键（点键盘上的键选 · 双击测试）",
                                                        en: "Trigger key (click a key · double-tap to test)"))
        keyLabel.font = .systemFont(ofSize: 13)
        root.addArrangedSubview(keyLabel)
        keyboard = KeyboardRowView()
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        keyboard.widthAnchor.constraint(equalToConstant: 412).isActive = true
        keyboard.heightAnchor.constraint(equalToConstant: 52).isActive = true
        keyboard.onSelect = { [weak self] t in self?.keyChanged(t) }
        root.addArrangedSubview(keyboard)
        keyStatus = NSTextField(labelWithString: "…")
        keyStatus.font = .systemFont(ofSize: 11); keyStatus.textColor = .secondaryLabelColor
        keyStatus.lineBreakMode = .byWordWrapping; keyStatus.preferredMaxLayoutWidth = 412
        root.addArrangedSubview(keyStatus)

        // 完成
        let doneBtn = NSButton(title: L.t(zh: "完成", en: "Done"), target: self, action: #selector(done))
        doneBtn.bezelStyle = .rounded; doneBtn.keyEquivalent = "\r"
        let footer = NSStackView(views: [NSView(), doneBtn])
        footer.orientation = .horizontal
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.widthAnchor.constraint(equalToConstant: 412).isActive = true
        root.addArrangedSubview(footer)

        let content = NSView()
        content.addSubview(root)
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

    /// 一行：左侧定宽标签 + 右侧控件（可继续 addArrangedSubview 加按钮）
    private func labeledRow(_ label: String, _ control: NSView) -> NSStackView {
        let l = NSTextField(labelWithString: label)
        l.font = .systemFont(ofSize: 13)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 60).isActive = true
        let row = NSStackView(views: [l, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 412).isActive = true
        return row
    }
}
