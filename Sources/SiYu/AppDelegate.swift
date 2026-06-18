import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let hotkey = HotkeyMonitor()
    private let readHotkey = HotkeyMonitor()   // 朗读选中文字的独立触发键
    private let dictation = Dictation()
    private let speaker = Speaker()
    private let hud = HUD()
    private var config = Config.load()
    private var statusItem: NSStatusItem!
    private var busy = false

    /// 朗读设置（语音/语速/触发键/试听），从设置向导进入。
    private lazy var readSetup = ReadSetup(readHotkey: readHotkey, speaker: speaker) { [weak self] kv in
        self?.persist(kv)
    }

    /// 热键设置（Typeless 式：选键 → 双击测试 → 确认才生效）。确认后持久化并刷新 UI。
    private lazy var hotkeySetup = HotkeySetup(hotkey: hotkey) { [weak self] id in
        guard let self else { return }
        self.config.triggerKey = id
        self.persist(["triggerKey": id])
        self.statusItem.button?.toolTip = L.t(zh: "丝语 · 双击\(self.hotkey.trigger.label) 开始/结束",
                                              en: "Dontype · double-tap \(self.hotkey.trigger.label) to start/stop")
        self.rebuildMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        L.set(config.uiLang)
        Whisper.configure(modelID: config.whisperModel, language: config.recognitionLang)
        setupStatusItem()

        // 剪贴历史（最多 5 条）：本 app 转写结果 + 监听用户手动复制；变化时刷新菜单
        RecallStore.shared.onChange = { [weak self] in self?.rebuildMenu() }
        RecallStore.shared.startMonitoring()

        // 药丸位置：恢复上次拖到的偏移；拖动后防抖持久化
        hud.setSavedOffset(CGPoint(x: config.pillOffsetX, y: config.pillOffsetY))
        hud.onOffsetChanged = { [weak self] o in
            guard let self else { return }
            self.config.pillOffsetX = Double(o.x); self.config.pillOffsetY = Double(o.y)
            self.persist(["pillOffsetX": Double(o.x), "pillOffsetY": Double(o.y)])
        }

        // 模型就绪先拉起常驻识别服务；缺模型/缺权限时由设置向导逐项引导（期间走 Apple 识别顶着）
        if Whisper.available { Whisper.startServer() }
        Onboarding.shared.onModelReady = { Whisper.startServer() }
        Onboarding.shared.onConfigureHotkey = { [weak self] in self?.hotkeySetup.show() }
        Onboarding.shared.onConfigureRead = { [weak self] in self?.readSetup.show() }
        Onboarding.shared.onChangeUILang = { [weak self] id in
            guard let self else { return }
            self.config.uiLang = id
            self.persist(["uiLang": id])
            L.set(id)
            self.rebuildMenu()   // 主菜单按新语言重绘（向导自己会重建）
        }
        Onboarding.shared.onChangeRecogLang = { [weak self] code in
            guard let self else { return }
            self.config.recognitionLang = code
            self.persist(["recognitionLang": code])
            Whisper.configure(modelID: self.config.whisperModel, language: code)
            Whisper.restartServer()   // 识别语言变了，重启识别服务生效
        }

        let guiding = Onboarding.shouldAutoShow()
        if guiding {
            Onboarding.shared.show()      // 分页向导（含隐私同意页），避免开屏连环弹窗
        } else {
            dictation.requestPermission { _ in }
            requestAccessibilityIfNeeded()
        }

        hotkey.setTrigger(Trigger.from(config.triggerKey))
        // 双击开始；录音中单击即停（停了之后消费 tap 计时，防止下一击被算成双击）
        hotkey.onDoubleTap = { [weak self] in
            guard let self, !self.dictation.isRecording else { return }
            self.startRecording()
        }
        hotkey.onSingleTap = { [weak self] in
            guard let self, self.dictation.isRecording else { return }
            self.stopAndProcess(paste: true)
        }
        // Esc：完成但不粘贴 —— 文字留在药丸上可点 copy，不会白录
        hotkey.onEscape = { [weak self] in
            guard let self, self.dictation.isRecording else { return }
            self.stopAndProcess(paste: false)
        }
        hotkey.start()

        // 朗读选中文字：独立触发键（默认双击 右⌘）—— 双击读、单击暂停/继续、Esc 停
        readHotkey.setTrigger(Trigger.from(config.readKey))
        readHotkey.onDoubleTap = { [weak self] in self?.startReading() }
        readHotkey.onSingleTap = { [weak self] in self?.togglePauseReading() }
        readHotkey.onEscape = { [weak self] in self?.stopReading() }
        readHotkey.start()
        speaker.onFinish = { [weak self] in self?.finishReading() }

        if !hotkey.isActive || !readHotkey.isActive {
            if !guiding { notifyAccessibilityNeeded() }
            // 授权可能稍后才生效：轮询等待，权限一到自动启动两个监听，免去手动重启
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                guard let self else { return }
                if AXIsProcessTrusted() {
                    self.hotkey.start()
                    self.readHotkey.start()
                    if self.hotkey.isActive && self.readHotkey.isActive {
                        self.retryTimer?.invalidate()
                        self.retryTimer = nil
                    }
                }
            }
        }
    }

    private var retryTimer: Timer?

    func applicationWillTerminate(_ notification: Notification) {
        Whisper.stopServer()
    }

    // MARK: 录音流程

    private func startRecording() {
        if busy { return }
        if speaker.isSpeaking { speaker.stop() }   // 开始说话前先停掉正在朗读的
        config = Config.load()      // 每次开始时重载，拾取菜单里的模式切换
        dictation.onLevel = { [weak self] lv in self?.hud.updateLevel(lv) }
        dictation.onError = { [weak self] msg in
            guard let self else { return }
            self.hotkey.recordingActive = false
            self.setIcon(.idle)
            self.busy = false
            self.hud.showError(msg)
        }
        do {
            try dictation.start(locale: config.locale, micUID: config.micDeviceUID)
            hud.showRecording(under: statusItemScreenRect(), micKind: dictation.sourceKind)
            hotkey.recordingActive = true
            setIcon(.recording)
        } catch {
            setIcon(.idle)
            hud.showError(error.localizedDescription,
                          micOff: dictation.sourceKind == .off,
                          under: statusItemScreenRect())
        }
    }

    /// 菜单栏图标的屏幕坐标，给录音药丸定位
    private func statusItemScreenRect() -> NSRect? {
        guard let button = statusItem.button, let win = button.window else { return nil }
        return win.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// paste=true（单击 Control）整理后粘贴到光标；paste=false（Esc）只展示+copy 按钮
    private func stopAndProcess(paste: Bool) {
        guard dictation.isRecording else { return }
        busy = true
        hotkey.recordingActive = false
        setIcon(.processing)
        hud.showProcessing()
        dictation.stop { [weak self] raw in
            guard let self else { return }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                self.hud.showError("没有识别到内容")
                self.setIcon(.idle)
                self.busy = false
                return
            }
            Cleaner.clean(text, config: self.config) { cleaned in
                let final = cleaned.isEmpty ? text : cleaned
                let doPaste = paste && self.config.autoPaste
                if doPaste { Paster.paste(final) }   // paste 内部会先写剪贴板
                self.hud.showResult(final, pasted: doPaste)
                RecallStore.shared.addFromApp(final)  // 进剪贴历史（来源：转写）；onChange 会刷新菜单
                self.setIcon(.idle)
                self.busy = false
            }
        }
    }

    // MARK: 朗读流程（朗读选中文字）

    /// 双击朗读键：抓当前选中文字 → premium 嗓音念出来。再双击当作停止。
    private func startReading() {
        guard !dictation.isRecording, !busy else { return }   // 录音/处理中不抢
        if speaker.isSpeaking { stopReading(); return }
        config = Config.load()
        // 抓文字可能要等剪贴板（~几十 ms），放后台，别卡主线程
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            // 优先「从 highlight 往下读到这个文本块结尾」；拿不到退回只读选中那段
            let text = TextGrabber.selectionToBlockEnd() ?? TextGrabber.selectedText()
            DispatchQueue.main.async {
                guard let text, !text.isEmpty else {
                    self.hud.flash(L.t(zh: "没有选中文字", en: "No text selected"),
                                   under: self.statusItemScreenRect())
                    return
                }
                self.speaker.speak(text, voiceID: self.config.readVoice, rate: self.config.readRate)
                self.readHotkey.recordingActive = true
                self.hud.showSpeaking(paused: false, under: self.statusItemScreenRect())
                FileLog.write("朗读开始（\(text.count) 字，嗓音=\(self.config.readVoice.isEmpty ? "自动" : self.config.readVoice)）")
            }
        }
    }

    /// 单击朗读键：暂停 ⇄ 继续
    private func togglePauseReading() {
        guard speaker.isSpeaking else { return }
        let paused = speaker.pauseOrResume()
        hud.showSpeaking(paused: paused, under: statusItemScreenRect())
    }

    /// Esc：停止朗读
    private func stopReading() {
        speaker.stop()   // → 触发 onFinish → finishReading
    }

    private func finishReading() {
        readHotkey.recordingActive = false
        if !dictation.isRecording { hud.hide() }   // 别误收起正在录音的药丸
        FileLog.write("朗读结束")
    }

    // MARK: 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.toolTip = L.t(zh: "丝语 · 双击\(hotkey.trigger.label) 开始/结束",
                                         en: "Dontype · double-tap \(hotkey.trigger.label) to start/stop")
        setIcon(.idle)
        rebuildMenu()
    }

    private func setIcon(_ state: MenuIcon.State) {
        statusItem.button?.image = MenuIcon.image(for: state)
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // ─── 语音输入（说话 → 文字）───
        menu.addItem(sectionHeader(L.t(zh: "语音输入 · 说话 → 文字", en: "Voice input · speech → text")))
        menu.addItem(hintItem(L.t(zh: "双击\(hotkey.trigger.label) 开始 · 单击结束 · Esc 不粘贴",
                                  en: "Double-tap \(hotkey.trigger.label) to start · tap to stop · Esc = no paste")))

        // 剪贴历史（最多 5 条，转写 + 手动复制）：点一下复制回剪贴板
        buildRecallItems().forEach { menu.addItem($0) }

        // 默认 = 自动判断；勾上 = 停用（永远不整理）
        let cleanupItem = NSMenuItem(title: L.t(zh: "停用 AI 整理（默认：自动判断）",
                                                en: "Disable AI cleanup (default: auto)"),
                                     action: #selector(toggleCleanup), keyEquivalent: "")
        cleanupItem.target = self
        cleanupItem.state = config.cleanup ? .off : .on   // cleanup=true → 自动→ 不勾；false → 停用 → 勾
        menu.addItem(cleanupItem)

        let pasteItem = NSMenuItem(title: L.t(zh: "自动粘贴到光标", en: "Auto-paste at cursor"),
                                   action: #selector(toggleAutoPaste), keyEquivalent: "")
        pasteItem.target = self
        pasteItem.state = config.autoPaste ? .on : .off
        menu.addItem(pasteItem)

        menu.addItem(buildMicMenu())

        menu.addItem(.separator())

        // ─── 朗读（文字 → 说话）───
        menu.addItem(sectionHeader(L.t(zh: "朗读 · 文字 → 说话", en: "Read aloud · text → speech")))
        menu.addItem(hintItem(L.t(zh: "选中后双击\(Trigger.from(config.readKey).label) 朗读 · 单击暂停/继续 · Esc 停",
                                  en: "Select, double-tap \(Trigger.from(config.readKey).label) to read · tap to pause · Esc to stop")))

        menu.addItem(.separator())

        // ─── 通用 ───（界面语言、模型、热键、朗读等都在「设置向导」里）
        let setup = NSMenuItem(title: L.t(zh: "设置向导…（界面语言 / 模型 / 热键 / 朗读…）",
                                          en: "Setup Wizard… (language / model / hotkeys / read…)"),
                               action: #selector(openOnboarding), keyEquivalent: "")
        setup.target = self
        menu.addItem(setup)

        let quit = NSMenuItem(title: L.t(zh: "退出丝语", en: "Quit Dontype"),
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    /// 小节标题：禁用、小号半粗次要色，读起来像分区标签而不是不可用的选项
    private func sectionHeader(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        it.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        return it
    }

    /// 操作提示行：禁用、次要色
    private func hintItem(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        it.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ])
        return it
    }

    /// 剪贴历史菜单项（最多 5 条）：每条带来源图标（转写=波形 / 复制=剪贴板）+ 预览，点击复制回剪贴板。
    private func buildRecallItems() -> [NSMenuItem] {
        let entries = RecallStore.shared.entries
        guard !entries.isEmpty else {
            let none = NSMenuItem(title: L.t(zh: "剪贴历史（暂无）", en: "Clipboard history (none)"),
                                  action: nil, keyEquivalent: "")
            none.isEnabled = false
            return [none]
        }
        var items: [NSMenuItem] = [
            hintItem(L.t(zh: "剪贴历史 · 点一下复制（最多 5 条）", en: "Clipboard history · click to copy (up to 5)"))
        ]
        for e in entries {
            let preview = e.text.replacingOccurrences(of: "\n", with: " ").prefix(28)
            let ell = e.text.count > 28 ? "…" : ""
            let item = NSMenuItem(title: "\(preview)\(ell)", action: #selector(recallEntry(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = e.text
            item.toolTip = e.text
            let sym = e.source == .dictation ? "waveform" : "doc.on.clipboard"
            item.image = NSImage(systemSymbolName: sym, accessibilityDescription: nil)
            items.append(item)
        }
        return items
    }

    /// 「麦克风」子菜单：列出当前可用输入设备。
    /// 「自动（智能选择）」= 跟随盖开/合盖逻辑；选某个设备 = 固定用它（拔出后下次自动回退）。
    private func buildMicMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: L.t(zh: "麦克风", en: "Microphone"), action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "micmenu")
        sub.delegate = self          // 打开前重新枚举设备
        populateMicMenu(sub)
        parent.submenu = sub
        return parent
    }

    /// 把可用设备填进麦克风子菜单（构建时 + 每次打开前都会调用）
    private func populateMicMenu(_ sub: NSMenu) {
        sub.removeAllItems()
        let manual = config.micDeviceUID

        // 顶部：自动选择 + 当前实际选中的设备名提示
        let auto = NSMenuItem(title: L.t(zh: "自动（智能选择）", en: "Automatic (smart)"),
                              action: #selector(pickMic(_:)), keyEquivalent: "")
        auto.target = self
        auto.representedObject = ""
        auto.state = manual.isEmpty ? .on : .off
        sub.addItem(auto)
        if manual.isEmpty, let (dev, why, _) = AudioDevices.smartPick() {
            let hint = NSMenuItem(title: L.t(zh: "  → 当前：\(dev.name)（\(why)）",
                                             en: "  → now: \(dev.name)"),
                                  action: nil, keyEquivalent: "")
            hint.isEnabled = false
            sub.addItem(hint)
        }
        sub.addItem(.separator())

        // 逐个列出可用输入设备，附来源图标
        let devices = AudioDevices.inputDevices()
        if devices.isEmpty {
            let none = NSMenuItem(title: L.t(zh: "（无可用输入设备）", en: "(no input device)"),
                                  action: nil, keyEquivalent: "")
            none.isEnabled = false
            sub.addItem(none)
        }
        for d in devices {
            let item = NSMenuItem(title: d.name, action: #selector(pickMic(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = d.uid
            item.state = (d.uid == manual) ? .on : .off
            item.image = MicIcon.image(for: AudioDevices.kind(of: d), size: 14)
            sub.addItem(item)
        }
    }

    @objc private func pickMic(_ sender: NSMenuItem) {
        config.micDeviceUID = (sender.representedObject as? String) ?? ""
        persist(["micDeviceUID": config.micDeviceUID])
        rebuildMenu()
    }

    // 麦克风子菜单打开前刷新设备列表（热插拔的耳机/iPhone 即时出现）
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.title == "micmenu" { populateMicMenu(menu) }
    }

    @objc private func toggleCleanup() {
        config.cleanup.toggle()
        persist(["cleanup": config.cleanup])
        rebuildMenu()
    }

    @objc private func toggleAutoPaste() {
        config.autoPaste.toggle()
        persist(["autoPaste": config.autoPaste])
        rebuildMenu()
    }

    @objc private func recallEntry(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        RecallStore.shared.recall(byText: text)   // 复制回剪贴板并置顶；自己 Cmd+V 粘到想要的地方
        FileLog.write("剪贴历史重取 → 已复制（\(text.count) 字）")
    }

    @objc private func openOnboarding() {
        Onboarding.shared.show(paginated: false)   // 菜单：开旧版设置面板（单窗口清单），不走分页向导
    }

    private func persist(_ kv: [String: Any]) {
        var json: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: Config.path),
           let existing = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            json = existing
        }
        kv.forEach { json[$0.key] = $0.value }
        try? FileManager.default.createDirectory(atPath: Config.dir, withIntermediateDirectories: true)
        if let out = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? out.write(to: URL(fileURLWithPath: Config.path))
        }
    }

    // MARK: 权限

    private func requestAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func notifyAccessibilityNeeded() {
        let alert = NSAlert()
        alert.messageText = L.t(zh: "需要「辅助功能」权限", en: "Accessibility permission needed")
        alert.informativeText = L.t(
            zh: "丝语需要辅助功能权限来监听\(hotkey.trigger.label)键、并把整理结果粘贴到光标处。\n\n请在「系统设置 ▸ 隐私与安全性 ▸ 辅助功能」中勾选 丝语，勾选后无需重启 App。",
            en: "Dontype needs Accessibility to watch the \(hotkey.trigger.label) key and paste at the cursor.\n\nEnable Dontype in System Settings ▸ Privacy & Security ▸ Accessibility. No restart needed.")
        alert.addButton(withTitle: L.t(zh: "打开系统设置", en: "Open System Settings"))
        alert.addButton(withTitle: L.t(zh: "稍后", en: "Later"))
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
