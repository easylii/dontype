import AppKit
import ApplicationServices

/// 开始/结束热键设置（Typeless 式）：选一个触发键 → **实际双击试一下** → 确认无误才真正启用。
/// 手势固定为「双击开始 · 单击结束 · Esc 取消」，这里让用户挑用哪个键来双击。
/// 测试期间把 live HotkeyMonitor 切到候选键 + testMode（双击只回调测试钩子、不会真的开始录音），
/// 取消或直接关窗则恢复原键。
final class HotkeySetup: NSObject, NSWindowDelegate {
    private let hotkey: HotkeyMonitor
    private let onApply: (String) -> Void   // 确认后：持久化 triggerKey + 刷新菜单

    init(hotkey: HotkeyMonitor, onApply: @escaping (String) -> Void) {
        self.hotkey = hotkey
        self.onApply = onApply
    }

    private var window: NSWindow?
    private var keyboard: KeyboardRowView!
    private var status: NSTextField!
    private var confirmButton: NSButton!

    private var originalTriggerID = "control"
    private var candidate: Trigger = .from("control")
    private var detected = false
    private var confirmed = false

    func show() {
        if window == nil { build() }
        originalTriggerID = hotkey.trigger.id
        candidate = hotkey.trigger
        confirmed = false
        keyboard.selectedID = candidate.id   // 虚拟键盘上高亮当前键
        beginTesting()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: 测试编排

    /// 进入候选键的测试态：切 live 监听到候选键 + testMode，等用户双击。
    private func beginTesting() {
        detected = false
        confirmButton.isEnabled = false
        hotkey.testMode = true
        hotkey.onTestDoubleTap = { [weak self] in self?.onDetected() }
        hotkey.setTrigger(candidate)

        if !hotkey.isActive {
            status.stringValue = L.t(zh: "⚠︎ 需要先在「设置向导」授予辅助功能权限，热键才能工作。",
                                     en: "⚠︎ Grant Accessibility in Setup first, then the hotkey can work.")
            status.textColor = .systemOrange
        } else {
            status.stringValue = L.t(zh: "请现在双击 \(candidate.label) 试一下…",
                                     en: "Now double-tap \(candidate.label) to test…")
            status.textColor = .secondaryLabelColor
        }
    }

    private func onDetected() {
        detected = true
        confirmButton.isEnabled = true
        keyboard.flash(candidate.id)        // 虚拟键盘上对应键闪绿
        status.stringValue = L.t(zh: "✓ 检测到「双击 \(candidate.label)」。确认无误就点「启用」。",
                                 en: "✓ Detected double-tap \(candidate.label). Click Enable to confirm.")
        status.textColor = .systemGreen
    }

    /// 关闭测试态；restore=true 时把 live 监听恢复成原触发键。
    private func endTesting(restore: Bool) {
        hotkey.testMode = false
        hotkey.onTestDoubleTap = nil
        if restore { hotkey.setTrigger(.from(originalTriggerID)) }
    }

    // MARK: 动作

    @objc private func confirm() {
        guard detected else { return }
        confirmed = true
        endTesting(restore: false)        // 保留候选键为 live 触发键
        onApply(candidate.id)             // 持久化 + 刷新菜单
        FileLog.write("热键已确认启用：双击 \(candidate.label)")
        window?.close()
    }

    @objc private func cancel() { window?.close() }   // windowWillClose 里恢复

    func windowWillClose(_ notification: Notification) {
        if !confirmed { endTesting(restore: true) }   // 没确认就关 → 恢复原键
    }

    // MARK: UI

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 230),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L.t(zh: "丝语 · 开始/结束热键", en: "Dontype · Start/Stop Hotkey")
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.delegate = self

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: L.t(zh: "选择触发键", en: "Choose a trigger key"))
        title.font = .boldSystemFont(ofSize: 15)
        let desc = NSTextField(labelWithString:
            L.t(zh: "在下面键盘上点一个键选它 · 手势固定：双击开始说话 / 单击结束粘贴 / Esc 结束不粘贴。",
                en: "Click a key below to pick it · gesture: double-tap to start / tap to stop & paste / Esc to stop without pasting."))
        desc.font = .systemFont(ofSize: 12)
        desc.textColor = .secondaryLabelColor
        desc.lineBreakMode = .byWordWrapping
        desc.preferredMaxLayoutWidth = 372

        keyboard = KeyboardRowView()
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        keyboard.widthAnchor.constraint(equalToConstant: 372).isActive = true
        keyboard.heightAnchor.constraint(equalToConstant: 52).isActive = true
        keyboard.onSelect = { [weak self] t in
            guard let self else { return }
            self.candidate = t
            self.keyboard.selectedID = t.id
            self.beginTesting()      // 换键 → 重新要求双击测试确认
        }

        status = NSTextField(labelWithString: "…")
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byWordWrapping
        status.preferredMaxLayoutWidth = 372

        confirmButton = NSButton(title: L.t(zh: "启用", en: "Enable"), target: self, action: #selector(confirm))
        confirmButton.bezelStyle = .rounded
        confirmButton.keyEquivalent = "\r"
        confirmButton.isEnabled = false
        let cancelButton = NSButton(title: L.t(zh: "取消", en: "Cancel"), target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        let buttons = NSStackView(views: [NSView(), cancelButton, confirmButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalToConstant: 372).isActive = true

        root.addArrangedSubview(title)
        root.addArrangedSubview(desc)
        root.addArrangedSubview(keyboard)
        root.addArrangedSubview(status)
        root.addArrangedSubview(buttons)

        let content = NSView()
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        w.contentView = content
        w.setContentSize(NSSize(width: 420, height: content.fittingSize.height))  // 高度随内容自适应
        window = w
    }
}
