import AppKit
import AVFoundation
import Speech
import ApplicationServices
import GameController

/// 顶部对齐的文档视图：放进 NSScrollView 后内容从上往下排、向下滚动。
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 设置向导（分页）：Welcome → 隐私 → 权限 → 模型 → 热键 → 朗读 → AI → 完成。
/// 底部进度点 + 上/下一步；隐私页未同意则「下一步」禁用。功能与原单页一致：
/// 三项权限、模型下载、识别语言、AI 后端测试、热键、朗读、界面语言。
final class Onboarding: NSObject {
    static let shared = Onboarding()

    private static let marker = Config.dir + "/.onboarded"
    private static let privacyMarker = Config.dir + "/.privacy-agreed"

    /// 是否该在启动时自动弹：未同意隐私 / 从未完成 / 仍缺关键项（辅助功能 / 模型）。
    static func shouldAutoShow() -> Bool {
        if !FileManager.default.fileExists(atPath: privacyMarker) { return true }
        if !FileManager.default.fileExists(atPath: marker) { return true }
        if !AXIsProcessTrusted() { return true }
        if !Whisper.available { return true }
        return false
    }

    private enum Page: Int, CaseIterable { case welcome, privacy, permissions, model, hotkey, read, ai, done }
    private var page: Page = .welcome
    private var privacyAgreed = FileManager.default.fileExists(atPath: privacyMarker)

    private var window: NSWindow?
    private var refreshTimer: Timer?
    private var config = Config.load()

    // 框架控件
    private var pageScroll: NSScrollView!
    private var backBtn: NSButton!, nextBtn: NSButton!
    private var dotsStack: NSStackView!
    private var pageCache: [Page: NSView] = [:]

    // 各页控件引用（refresh 时更新；按页懒建，故为可选）
    private var micDetail: NSTextField?,    micButton: NSButton?
    private var speechDetail: NSTextField?, speechButton: NSButton?
    private var axDetail: NSTextField?,     axButton: NSButton?
    private var modelDetail: NSTextField?,  modelButton: NSButton?,  modelBar: NSProgressIndicator?
    private var backendDetail: NSTextField?, backendButton: NSButton?
    private var cleanupBackendPopup: NSPopUpButton?
    private var hotkeyDetail: NSTextField?
    private var readDetail: NSTextField?,   readButton: NSButton?
    private var remoteDetail: NSTextField?, remoteSwitch: NSButton?
    private var remoteConnChecking = false
    private var consentStatus: NSTextField?

    var onModelReady: (() -> Void)?
    var onConfigureHotkey: (() -> Void)?
    var onConfigureRead: (() -> Void)?
    var onChangeUILang: ((String) -> Void)?
    var onChangeRecogLang: ((String) -> Void)?
    var onChangeCleanupBackend: ((String) -> Void)?
    var onChangeRemoteEnabled: ((Bool) -> Void)?
    var onConfigureRemote: (() -> Void)?

    private let uiLangIDs = ["auto", "zh", "en"]

    // 品牌蓝（和 demo 同色）+ SF Rounded 圆体（等效 Nunito，系统内置）
    private let accent = NSColor(srgbRed: 0x2E/255.0, green: 0x7B/255.0, blue: 0xE0/255.0, alpha: 1)
    private var dotWidths: [NSLayoutConstraint] = []

    private func rounded(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(.rounded) { return NSFont(descriptor: d, size: size) ?? base }
        return base
    }

    // MARK: 打开 / 关闭

    /// paginated=true：首次安装的分页向导（Welcome→隐私→…→完成）。
    /// paginated=false：菜单里重开的「设置面板」——单窗口清单，不走分页流程。
    private var paginated = true

    func show(paginated: Bool = true) {
        config = Config.load()
        privacyAgreed = FileManager.default.fileExists(atPath: Onboarding.privacyMarker)
        // 模式变了就拆掉旧窗口重建（向导 ↔ 面板共用控件引用，一次只开一个）
        if window != nil && self.paginated != paginated {
            window?.orderOut(nil); window = nil
            pageCache.removeAll(); clearRefs()
        }
        self.paginated = paginated
        if window == nil { paginated ? build() : buildPanel() }
        if paginated { showPage(page) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.center()
        startRefresh()
    }

    private func clearRefs() {
        micDetail = nil; micButton = nil; speechDetail = nil; speechButton = nil
        axDetail = nil; axButton = nil; modelDetail = nil; modelButton = nil; modelBar = nil
        backendDetail = nil; backendButton = nil; cleanupBackendPopup = nil; hotkeyDetail = nil
        readDetail = nil; readButton = nil; consentStatus = nil
        remoteDetail = nil; remoteSwitch = nil
    }

    private func startRefresh() {
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func finish() {
        try? "ok".write(toFile: Onboarding.marker, atomically: true, encoding: .utf8)
        refreshTimer?.invalidate(); refreshTimer = nil
        window?.orderOut(nil)
    }

    // MARK: 框架

    private func build() {
        let W: CGFloat = 480, H: CGFloat = 470
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: H),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L.t(zh: "丝语 · 设置向导", en: "Dontype · Setup")
        w.isReleasedWhenClosed = false
        w.level = .floating

        let content = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))

        // 底部导航栏
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false

        backBtn = NSButton(title: L.t(zh: "上一步", en: "Back"), target: self, action: #selector(goBack))
        backBtn.bezelStyle = .rounded
        backBtn.translatesAutoresizingMaskIntoConstraints = false

        nextBtn = NSButton(title: L.t(zh: "下一步", en: "Next"), target: self, action: #selector(goNext))
        nextBtn.bezelStyle = .rounded
        nextBtn.keyEquivalent = "\r"
        nextBtn.translatesAutoresizingMaskIntoConstraints = false

        dotsStack = NSStackView()
        dotsStack.orientation = .horizontal
        dotsStack.spacing = 6
        dotsStack.translatesAutoresizingMaskIntoConstraints = false
        dotWidths.removeAll()
        for _ in Page.allCases {
            let d = NSView()
            d.wantsLayer = true
            d.layer?.cornerRadius = 3.5
            d.translatesAutoresizingMaskIntoConstraints = false
            let wc = d.widthAnchor.constraint(equalToConstant: 7); wc.isActive = true
            dotWidths.append(wc)
            d.heightAnchor.constraint(equalToConstant: 7).isActive = true
            dotsStack.addArrangedSubview(d)
        }

        footer.addSubview(backBtn); footer.addSubview(nextBtn); footer.addSubview(dotsStack)

        let sep = NSBox(); sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false

        pageScroll = NSScrollView()
        pageScroll.drawsBackground = false
        pageScroll.hasVerticalScroller = true
        pageScroll.autohidesScrollers = true
        pageScroll.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(pageScroll); content.addSubview(sep); content.addSubview(footer)
        NSLayoutConstraint.activate([
            pageScroll.topAnchor.constraint(equalTo: content.topAnchor),
            pageScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            pageScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            pageScroll.bottomAnchor.constraint(equalTo: sep.topAnchor),

            sep.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 56),

            backBtn.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 22),
            backBtn.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            nextBtn.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -22),
            nextBtn.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            dotsStack.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
            dotsStack.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])

        w.contentView = content
        window = w
    }

    /// 旧版「设置面板」：单窗口、从上往下滚动的清单（菜单里重开用，不走分页向导）。
    private func buildPanel() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L.t(zh: "丝语 · 设置", en: "Dontype · Settings")
        w.isReleasedWhenClosed = false
        w.level = .floating

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: L.t(zh: "设置", en: "Settings"))
        title.font = rounded(17, .bold)
        let subtitle = NSTextField(labelWithString:
            L.t(zh: "随时查看与调整。每项右侧按钮一键处理，状态自动刷新。",
                en: "Review and adjust anytime. Tap a button; status refreshes automatically."))
        subtitle.font = .systemFont(ofSize: 12); subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byWordWrapping; subtitle.preferredMaxLayoutWidth = 432
        root.addArrangedSubview(title)
        root.addArrangedSubview(subtitle)
        root.addArrangedSubview(separator())

        let mic = row(title: L.t(zh: "① 麦克风权限", en: "① Microphone"),
                      button: L.t(zh: "请求", en: "Grant"), action: #selector(reqMic))
        micDetail = mic.detail; micButton = mic.button
        root.addArrangedSubview(mic.view)

        let sp = row(title: L.t(zh: "② 语音识别权限（备用后端）", en: "② Speech Recognition (fallback)"),
                     button: L.t(zh: "请求", en: "Grant"), action: #selector(reqSpeech))
        speechDetail = sp.detail; speechButton = sp.button
        root.addArrangedSubview(sp.view)

        let ax = row(title: L.t(zh: "③ 辅助功能权限（监听热键 / 自动粘贴）", en: "③ Accessibility (hotkey / paste)"),
                     button: L.t(zh: "打开设置", en: "Open Settings"), action: #selector(openAX))
        axDetail = ax.detail; axButton = ax.button
        root.addArrangedSubview(ax.view)

        root.addArrangedSubview(separator())

        let model = row(title: L.t(zh: "④ 识别模型", en: "④ Speech model"),
                        button: L.t(zh: "下载", en: "Download"), action: #selector(downloadModel))
        modelDetail = model.detail; modelButton = model.button
        let bar = NSProgressIndicator()
        bar.style = .bar; bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 1
        bar.isHidden = true
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 8).isActive = true
        modelBar = bar
        model.textStack.addArrangedSubview(bar)
        bar.widthAnchor.constraint(equalTo: model.textStack.widthAnchor).isActive = true
        root.addArrangedSubview(model.view)

        root.addArrangedSubview(recogLangRow())

        let backend = row(title: L.t(zh: "⑥ AI 整理后端", en: "⑥ AI cleanup backend"),
                          button: L.t(zh: "测试", en: "Test"), action: #selector(testBackend))
        backendDetail = backend.detail; backendButton = backend.button
        root.addArrangedSubview(backend.view)
        root.addArrangedSubview(cleanupBackendRow())

        let hk = row(title: L.t(zh: "⑦ 热键（听写 / 朗读 / 语音助手）", en: "⑦ Hotkeys (dictation / read / assistant)"),
                     button: L.t(zh: "设置", en: "Configure"), action: #selector(configureHotkey))
        hotkeyDetail = hk.detail
        root.addArrangedSubview(hk.view)

        root.addArrangedSubview(remoteRow())

        let rd = row(title: L.t(zh: "⑨ 朗读声音（语音 / 语速）", en: "⑨ Read-aloud voice (voice / speed)"),
                     button: L.t(zh: "设置", en: "Configure"), action: #selector(readButtonTapped))
        readDetail = rd.detail; readButton = rd.button
        root.addArrangedSubview(rd.view)

        root.addArrangedSubview(uiLangRow())

        root.addArrangedSubview(separator())

        let done = NSButton(title: L.t(zh: "完成", en: "Done"), target: self, action: #selector(finishSetup))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        let footer = NSStackView(views: [NSView(), done])
        footer.orientation = .horizontal
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.widthAnchor.constraint(equalToConstant: 432).isActive = true
        root.addArrangedSubview(footer)

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            root.topAnchor.constraint(equalTo: doc.topAnchor),
            root.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            doc.widthAnchor.constraint(equalToConstant: 480),
        ])
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = doc

        let contentH = root.fittingSize.height
        let maxH = min(660, (NSScreen.main?.visibleFrame.height ?? 800) - 80)
        w.contentView = scroll
        w.setContentSize(NSSize(width: 480, height: min(maxH, contentH)))
        window = w
    }

    private func separator() -> NSView {
        let line = NSBox(); line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: 424).isActive = true
        return line
    }

    private func uiLangRow() -> NSView {
        let titleLabel = NSTextField(labelWithString: L.t(zh: "⑩ 界面语言", en: "⑩ Interface language"))
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let seg = NSSegmentedControl(labels: [L.t(zh: "自动", en: "Auto"), "中文", "EN"],
                                     trackingMode: .selectOne, target: self, action: #selector(uiLangChanged(_:)))
        if let i = uiLangIDs.firstIndex(of: config.uiLang) { seg.selectedSegment = i }
        seg.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        let rowStack = NSStackView(views: [titleLabel, seg])
        rowStack.orientation = .horizontal; rowStack.alignment = .centerY; rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.widthAnchor.constraint(equalToConstant: 424).isActive = true
        return rowStack
    }

    @objc private func finishSetup() { finish() }

    // MARK: 翻页

    @objc private func goNext() {
        if page == .privacy && !privacyAgreed { return }
        if page == .done { finish(); return }
        if let nx = Page(rawValue: page.rawValue + 1) { page = nx; showPage(page) }
    }

    @objc private func goBack() {
        if let pv = Page(rawValue: page.rawValue - 1) { page = pv; showPage(page) }
    }

    private func showPage(_ p: Page) {
        let v = pageCache[p] ?? { let nv = buildPage(p); pageCache[p] = nv; return nv }()
        pageScroll.documentView = v
        v.wantsLayer = true
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.26
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        v.layer?.add(fade, forKey: "fadeIn")
        backBtn.isHidden = (p == .welcome)
        nextBtn.title = (p == .done) ? L.t(zh: "完成 · 开始使用", en: "Done · Start")
                                     : L.t(zh: "下一步", en: "Next")
        updateNextGate()
        updateDots()
        refresh()
    }

    private func updateNextGate() {
        nextBtn.isEnabled = !(page == .privacy && !privacyAgreed)
    }

    private func updateDots() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            for (i, d) in dotsStack.arrangedSubviews.enumerated() {
                let on = i == page.rawValue
                d.layer?.backgroundColor = (on ? accent : NSColor.tertiaryLabelColor).cgColor
                if i < dotWidths.count { dotWidths[i].animator().constant = on ? 18 : 7 }
            }
        }
    }

    // MARK: 页面构建

    private func buildPage(_ p: Page) -> NSView {
        switch p {
        case .welcome:     return welcomePage()
        case .privacy:     return privacyPage()
        case .permissions: return permissionsPage()
        case .model:       return modelPage()
        case .hotkey:      return hotkeyPage()
        case .read:        return readPage()
        case .ai:          return aiPage()
        case .done:        return donePage()
        }
    }

    /// 居中页（Welcome / 完成）。
    private func centerPage(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        return hostFlipped(stack, centered: true)
    }

    /// 步骤页：彩色图标 + 大标题（圆体）+ 说明 + 内容行。
    private func stepPage(icon: String, heading: String, note: String, body: [NSView]) -> NSView {
        let iconView = NSImageView()
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            iconView.image = img.withSymbolConfiguration(.init(pointSize: 17, weight: .semibold))
        }
        iconView.contentTintColor = accent
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 22).isActive = true

        let h = NSTextField(labelWithString: heading)
        h.font = rounded(16, .bold)
        let head = NSStackView(views: [iconView, h])
        head.orientation = .horizontal; head.alignment = .centerY; head.spacing = 8

        let n = NSTextField(wrappingLabelWithString: note)
        n.font = .systemFont(ofSize: 12); n.textColor = .secondaryLabelColor
        n.preferredMaxLayoutWidth = 424
        let stack = NSStackView(views: [head, n] + body)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(16, after: n)
        return hostFlipped(stack, centered: false)
    }

    /// 把内容栈包进与滚动视图等宽（480）的文档视图。
    private func hostFlipped(_ stack: NSStackView, centered: Bool) -> NSView {
        stack.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        NSLayoutConstraint.activate([
            doc.widthAnchor.constraint(equalToConstant: 480),
            stack.topAnchor.constraint(equalTo: doc.topAnchor, constant: centered ? 40 : 26),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -20),
        ])
        if centered {
            stack.centerXAnchor.constraint(equalTo: doc.centerXAnchor).isActive = true
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 400).isActive = true
        } else {
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 28).isActive = true
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -28).isActive = true
        }
        return doc
    }

    // 0 · Welcome
    private func welcomePage() -> NSView {
        let logo = NSImageView()
        logo.image = NSApp.applicationIconImage
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.widthAnchor.constraint(equalToConstant: 72).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 72).isActive = true

        let title = NSTextField(labelWithString: L.t(zh: "欢迎使用 Dontype", en: "Welcome to Dontype"))
        title.font = rounded(21, .bold); title.alignment = .center

        let tag = NSTextField(labelWithString: L.t(zh: "说出来，不用打字 —— 也能听。", en: "Stop typing. Just talk and listen."))
        tag.font = rounded(13, .medium); tag.textColor = .secondaryLabelColor; tag.alignment = .center

        let sub = NSTextField(wrappingLabelWithString:
            L.t(zh: "说话即成文字，选中即可朗读。全程本地识别，隐私不出本机。",
                en: "Speak to type, select to read aloud. All on-device — your voice never leaves your Mac."))
        sub.font = .systemFont(ofSize: 12); sub.textColor = .secondaryLabelColor
        sub.alignment = .center; sub.preferredMaxLayoutWidth = 360

        // 界面语言（提前让用户选）
        let langLabel = NSTextField(labelWithString: L.t(zh: "界面语言", en: "Language"))
        langLabel.font = .systemFont(ofSize: 11); langLabel.textColor = .tertiaryLabelColor
        let seg = NSSegmentedControl(labels: [L.t(zh: "自动", en: "Auto"), "中文", "EN"],
                                     trackingMode: .selectOne, target: self, action: #selector(uiLangChanged(_:)))
        if let i = uiLangIDs.firstIndex(of: config.uiLang) { seg.selectedSegment = i }
        let langRow = NSStackView(views: [langLabel, seg])
        langRow.orientation = .horizontal; langRow.spacing = 8

        let by = NSTextField(labelWithString: L.t(zh: "由 Easylii 出品", en: "by Easylii"))
        by.font = .systemFont(ofSize: 11); by.textColor = .tertiaryLabelColor; by.alignment = .center

        let v = centerPage([logo, title, tag, sub, spacer(8), langRow, spacer(4), by])
        return v
    }

    // 1 · 隐私
    private func privacyPage() -> NSView {
        let r1 = bulletRow(L.t(zh: "声音不离开你的 Mac", en: "Your voice stays on your Mac"),
                           L.t(zh: "语音在本机识别，绝不上传、不录存", en: "Recognized locally — never uploaded or stored"))
        let r2 = bulletRow(L.t(zh: "无跟踪 · 无分析 · 无账号", en: "No tracking · no analytics · no account"),
                           L.t(zh: "不收集任何个人数据，不出售数据", en: "We collect no personal data and sell nothing"))
        let r3 = bulletRow(L.t(zh: "AI 整理用你自己的账号", en: "AI cleanup uses your own account"),
                           L.t(zh: "开启时转写文字经你自己的 Claude / Codex 处理，可关闭",
                               en: "When on, text goes through your own Claude / Codex; optional"))

        let law = NSTextField(wrappingLabelWithString:
            L.t(zh: "符合 GDPR、CCPA 等隐私法规。", en: "Compliant with GDPR, CCPA and similar."))
        law.font = .systemFont(ofSize: 11); law.textColor = .tertiaryLabelColor
        law.preferredMaxLayoutWidth = 424

        let readBtn = NSButton(title: L.t(zh: "阅读隐私政策", en: "Read Privacy Policy"),
                               target: self, action: #selector(openPolicy))
        readBtn.bezelStyle = .rounded

        let status = NSTextField(labelWithString: L.t(zh: "阅读并同意后才能继续", en: "Read and agree to continue"))
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        consentStatus = status
        if privacyAgreed { status.stringValue = "✓ " + L.t(zh: "已阅读并同意隐私政策", en: "Read and agreed"); status.textColor = .systemGreen }

        let consentRow = NSStackView(views: [readBtn, status])
        consentRow.orientation = .horizontal; consentRow.spacing = 11; consentRow.alignment = .centerY

        return stepPage(icon: "lock.shield", heading: L.t(zh: "隐私优先", en: "Privacy first"),
                        note: L.t(zh: "你的声音永不离开这台 Mac。零收集、零追踪、无账号、无埋点。",
                                  en: "Your voice never leaves your Mac. No collection, no tracking, no accounts."),
                        body: [r1, r2, r3, spacer(6), law, consentRow])
    }

    // 2 · 权限
    private func permissionsPage() -> NSView {
        let mic = row(title: L.t(zh: "麦克风", en: "Microphone"),
                      button: L.t(zh: "请求", en: "Grant"), action: #selector(reqMic))
        micDetail = mic.detail; micButton = mic.button
        let sp = row(title: L.t(zh: "语音识别（备用后端）", en: "Speech Recognition (fallback)"),
                     button: L.t(zh: "请求", en: "Grant"), action: #selector(reqSpeech))
        speechDetail = sp.detail; speechButton = sp.button
        let ax = row(title: L.t(zh: "辅助功能（监听热键 / 自动粘贴）", en: "Accessibility (hotkey / paste)"),
                     button: L.t(zh: "打开设置", en: "Open Settings"), action: #selector(openAX))
        axDetail = ax.detail; axButton = ax.button
        return stepPage(icon: "checkmark.shield", heading: L.t(zh: "基础权限", en: "Permissions"),
                        note: L.t(zh: "这三项给齐，就能开始说话转文字。点按钮逐个允许，状态自动刷新。",
                                  en: "Grant these three to start dictating. Status refreshes automatically."),
                        body: [mic.view, sp.view, ax.view])
    }

    // 3 · 模型
    private func modelPage() -> NSView {
        let model = row(title: L.t(zh: "识别模型", en: "Speech model"),
                        button: L.t(zh: "下载", en: "Download"), action: #selector(downloadModel))
        modelDetail = model.detail; modelButton = model.button
        let bar = NSProgressIndicator()
        bar.style = .bar; bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 1
        bar.isHidden = true
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 8).isActive = true
        modelBar = bar
        model.textStack.addArrangedSubview(bar)
        bar.widthAnchor.constraint(equalTo: model.textStack.widthAnchor).isActive = true

        return stepPage(icon: "arrow.down.circle", heading: L.t(zh: "下载识别模型", en: "Download speech model"),
                        note: L.t(zh: "最高精度的本地模型（约 1.5GB，一次性）。下载时先用系统识别顶着。",
                                  en: "Top-accuracy local model (~1.5GB, one-time). Apple speech covers you meanwhile."),
                        body: [model.view, recogLangRow()])
    }

    // 4 · 热键
    private func hotkeyPage() -> NSView {
        let hk = row(title: L.t(zh: "开始 / 结束热键", en: "Start / stop hotkey"),
                     button: L.t(zh: "设置", en: "Configure"), action: #selector(configureHotkey))
        hotkeyDetail = hk.detail
        return stepPage(icon: "keyboard", heading: L.t(zh: "确认开始 / 结束热键", en: "Confirm your hotkey"),
                        note: L.t(zh: "双击触发键开始说话，单击结束并粘贴，Esc 取消。点「设置」可换键并测试。",
                                  en: "Double-tap to start, tap to stop & paste, Esc to cancel. Configure to change & test."),
                        body: [hk.view])
    }

    // 5 · 朗读
    private func readPage() -> NSView {
        let rd = row(title: L.t(zh: "朗读选中文字", en: "Read selection aloud"),
                     button: L.t(zh: "设置", en: "Configure"), action: #selector(readButtonTapped))
        readDetail = rd.detail; readButton = rd.button
        return stepPage(icon: "speaker.wave.2", heading: L.t(zh: "朗读选中文字（可选）", en: "Read selection aloud (optional)"),
                        note: L.t(zh: "双击右⌘ 从选中处往下朗读，单击暂停 / 继续，Esc 停止。嗓音与语速自动选最佳。",
                                  en: "Double-tap right ⌘ to read from the selection. Voice & rate auto-chosen."),
                        body: [rd.view])
    }

    // 6 · AI
    private func aiPage() -> NSView {
        let backend = row(title: L.t(zh: "AI 整理后端", en: "AI cleanup backend"),
                          button: L.t(zh: "测试", en: "Test"), action: #selector(testBackend))
        backendDetail = backend.detail; backendButton = backend.button
        return stepPage(icon: "sparkles", heading: L.t(zh: "AI 整理（可选）", en: "AI cleanup (optional)"),
                        note: L.t(zh: "装了 Claude Code 或 Codex 会自动启用，顺一遍口语、补标点、连成句子。也可填 API key。",
                                  en: "Auto-enabled if Claude Code or Codex is installed. Or set an API key."),
                        body: [backend.view])
    }

    // 7 · 完成
    private func donePage() -> NSView {
        let logo = NSImageView()
        logo.image = NSApp.applicationIconImage
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.widthAnchor.constraint(equalToConstant: 76).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 76).isActive = true

        let title = NSTextField(labelWithString: L.t(zh: "一切就绪", en: "All set"))
        title.font = rounded(21, .bold); title.alignment = .center

        let tl = Trigger.from(config.triggerKey).label
        let sub = NSTextField(wrappingLabelWithString:
            L.t(zh: "在任何 App 里双击 \(tl) 开始说话，单击 \(tl) 结束，文字直接落到光标处。",
                en: "Anywhere, double-tap \(tl) to talk, tap \(tl) to stop. Text lands at your cursor."))
        sub.font = .systemFont(ofSize: 12); sub.textColor = .secondaryLabelColor
        sub.alignment = .center; sub.preferredMaxLayoutWidth = 360

        return centerPage([logo, title, sub])
    }

    // MARK: 小工具

    private func spacer(_ h: CGFloat) -> NSView {
        let v = NSView(); v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: h).isActive = true
        return v
    }

    private func bulletRow(_ title: String, _ note: String) -> NSView {
        let dot = NSTextField(labelWithString: "✓")
        dot.font = .boldSystemFont(ofSize: 12); dot.textColor = .systemGreen
        let t = NSTextField(labelWithString: title); t.font = .systemFont(ofSize: 13, weight: .medium)
        let n = NSTextField(labelWithString: note); n.font = .systemFont(ofSize: 11); n.textColor = .secondaryLabelColor
        let textStack = NSStackView(views: [t, n]); textStack.orientation = .vertical; textStack.alignment = .leading; textStack.spacing = 2
        let row = NSStackView(views: [dot, textStack]); row.orientation = .horizontal; row.alignment = .firstBaseline; row.spacing = 9
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    /// 一行：左标题+状态，右动作按钮。textStack 可继续塞进度条。
    private func row(title: String, button: String, action: Selector)
        -> (view: NSView, textStack: NSStackView, detail: NSTextField, button: NSButton) {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        let detail = NSTextField(labelWithString: "…")
        detail.font = .systemFont(ofSize: 11); detail.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [titleLabel, detail])
        textStack.orientation = .vertical; textStack.alignment = .leading; textStack.spacing = 3
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let btn = NSButton(title: button, target: self, action: action)
        btn.bezelStyle = .rounded
        btn.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let rowStack = NSStackView(views: [textStack, btn])
        rowStack.orientation = .horizontal; rowStack.alignment = .centerY; rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.widthAnchor.constraint(equalToConstant: 424).isActive = true
        return (rowStack, textStack, detail, btn)
    }

    private func recogLangRow() -> NSView {
        let titleLabel = NSTextField(labelWithString: L.t(zh: "主要输入语言（识别 + 整理输出，不翻译）",
                                                          en: "Primary input language (recognize + clean, no translate)"))
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.target = self; popup.action = #selector(recogLangChanged(_:))
        for lang in Whisper.languages { popup.addItem(withTitle: Whisper.languageDisplay(lang.code)) }
        if let i = Whisper.languages.firstIndex(where: { $0.code == config.recognitionLang }) { popup.selectItem(at: i) }
        popup.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let rowStack = NSStackView(views: [titleLabel, popup])
        rowStack.orientation = .horizontal; rowStack.alignment = .centerY; rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.widthAnchor.constraint(equalToConstant: 424).isActive = true
        return rowStack
    }

    @objc private func recogLangChanged(_ sender: NSPopUpButton) {
        onChangeRecogLang?(Whisper.languages[max(0, sender.indexOfSelectedItem)].code)
    }

    /// 整理后端手动选择（auto / Claude API / Claude Code / Codex）。
    private func cleanupBackendRow() -> NSView {
        let titleLabel = NSTextField(labelWithString: L.t(zh: "　　整理用", en: "    Use backend"))
        titleLabel.font = .systemFont(ofSize: 12); titleLabel.textColor = .secondaryLabelColor
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.target = self; popup.action = #selector(cleanupBackendChanged(_:))
        popup.autoenablesItems = false   // 自己控制：没装/缺 key 的置灰
        for b in Cleaner.backends {
            let ready = Cleaner.backendReady(b.id, config: config)
            var title = L.t(zh: b.zh, en: b.en)
            if b.id != "auto" && !ready {
                title += b.id == "api" ? L.t(zh: " — 缺 key", en: " — no key")
                                       : L.t(zh: " — 未安装", en: " — not installed")
            }
            popup.addItem(withTitle: title)
            popup.lastItem?.isEnabled = (b.id == "auto") || ready
        }
        if let i = Cleaner.backends.firstIndex(where: { $0.id == config.cleanupBackend }) { popup.selectItem(at: i) }
        popup.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        cleanupBackendPopup = popup

        let rowStack = NSStackView(views: [titleLabel, popup])
        rowStack.orientation = .horizontal; rowStack.alignment = .centerY; rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.widthAnchor.constraint(equalToConstant: 424).isActive = true
        return rowStack
    }

    @objc private func cleanupBackendChanged(_ sender: NSPopUpButton) {
        onChangeCleanupBackend?(Cleaner.backends[max(0, sender.indexOfSelectedItem)].id)
        refresh()   // 立刻刷新「当前后端」那行的名字/可用性
    }


    /// 遥控器 / 手柄：「开 / 关」+ 连接状态 +「设置」打开演示 / 按键映射窗口。
    private func remoteRow() -> NSView {
        let titleLabel = NSTextField(labelWithString: L.t(zh: "⑧ 遥控器 / 手柄", en: "⑧ Remote / controller"))
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let sw = NSButton(checkboxWithTitle: L.t(zh: "启用", en: "On"),
                          target: self, action: #selector(remoteEnabledChanged))
        sw.state = config.remoteEnabled ? .on : .off
        remoteSwitch = sw

        let helpBtn = NSButton(title: L.t(zh: "设置…", en: "Set up…"),
                               target: self, action: #selector(configureRemote))
        helpBtn.bezelStyle = .rounded

        let top = NSStackView(views: [titleLabel, sw, helpBtn])
        top.orientation = .horizontal; top.alignment = .centerY; top.spacing = 12

        let detail = NSTextField(labelWithString: "…")
        detail.font = .systemFont(ofSize: 11); detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byWordWrapping; detail.preferredMaxLayoutWidth = 424
        remoteDetail = detail

        let stack = NSStackView(views: [top, detail])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 424).isActive = true
        return stack
    }

    @objc private func remoteEnabledChanged() {
        config.remoteEnabled = (remoteSwitch?.state == .on)
        onChangeRemoteEnabled?(config.remoteEnabled)
        updateRemoteStatus()
    }

    @objc private func configureRemote() { onConfigureRemote?() }

    /// 状态行：关 →「已关闭」；开 → 后台查蓝牙，显示已连接 / 未连接。
    private func updateRemoteStatus() {
        guard let remoteDetail else { return }
        if !config.remoteEnabled {
            remoteDetail.stringValue = "• " + L.t(zh: "已关闭", en: "Off")
            remoteDetail.textColor = .secondaryLabelColor
            return
        }
        guard !remoteConnChecking else { return }
        remoteConnChecking = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let on = RemoteHID.isConnectedBT()
            DispatchQueue.main.async {
                guard let self else { return }
                self.remoteConnChecking = false
                guard let d = self.remoteDetail, self.config.remoteEnabled else { return }
                if on {
                    d.stringValue = "✓ " + L.t(zh: "遥控器已连接", en: "Remote connected")
                    d.textColor = .systemGreen
                } else {
                    d.stringValue = "○ " + L.t(zh: "未连接（拿起遥控器按任意键唤醒）", en: "Not connected (press any key to wake)")
                    d.textColor = .secondaryLabelColor
                }
            }
        }
    }

    @objc private func uiLangChanged(_ sender: NSSegmentedControl) {
        let id = uiLangIDs[max(0, sender.selectedSegment)]
        onChangeUILang?(id)
        DispatchQueue.main.async { [weak self] in self?.relocalize() }
    }

    /// 切语言后用新语言重建向导，停在当前页。
    private func relocalize() {
        let keep = page
        let mode = paginated
        refreshTimer?.invalidate(); refreshTimer = nil
        window?.orderOut(nil); window = nil
        pageCache.removeAll(); clearRefs()
        config = Config.load()
        page = keep
        show(paginated: mode)
    }

    // MARK: 状态刷新（仅更新已建出来的页的控件）

    private func refresh() {
        if let micDetail, let micButton {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: ok(micDetail, L.t(zh: "已授权", en: "Granted")); micButton.isHidden = true
            case .denied, .restricted:
                bad(micDetail, L.t(zh: "已拒绝，请到设置开启", en: "Denied — enable in Settings"))
                micButton.title = L.t(zh: "打开设置", en: "Settings"); micButton.isHidden = false
            default:
                wait(micDetail, L.t(zh: "未授权", en: "Not granted"))
                micButton.title = L.t(zh: "请求", en: "Grant"); micButton.isHidden = false
            }
        }
        if let speechDetail, let speechButton {
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: ok(speechDetail, L.t(zh: "已授权", en: "Granted")); speechButton.isHidden = true
            case .denied, .restricted:
                bad(speechDetail, L.t(zh: "已拒绝（仅影响备用后端）", en: "Denied (fallback only)"))
                speechButton.title = L.t(zh: "打开设置", en: "Settings"); speechButton.isHidden = false
            default:
                wait(speechDetail, L.t(zh: "未授权（可选）", en: "Not granted (optional)"))
                speechButton.title = L.t(zh: "请求", en: "Grant"); speechButton.isHidden = false
            }
        }
        if let axDetail, let axButton {
            if AXIsProcessTrusted() {
                ok(axDetail, L.t(zh: "已授权", en: "Granted")); axButton.isHidden = true
            } else {
                bad(axDetail, L.t(zh: "未授权——勾选「Dontype」后自动生效", en: "Not granted — check Dontype in the list"))
                axButton.isHidden = false
            }
        }
        if let modelDetail, let modelButton, let modelBar {
            if ModelDownloader.shared.isDownloading {
                modelButton.isHidden = true
            } else if Whisper.available {
                ok(modelDetail, L.t(zh: "已就绪：\(Whisper.current.display)", en: "Ready: \(Whisper.current.display)"))
                modelButton.isHidden = true; modelBar.isHidden = true
            } else {
                let mb = Whisper.current.sizeMB
                wait(modelDetail, L.t(zh: "未下载（约 \(mb) MB，一次性）", en: "Not downloaded (~\(mb) MB, one-time)"))
                modelButton.title = L.t(zh: "下载", en: "Download"); modelButton.isHidden = false; modelBar.isHidden = true
            }
        }
        if let backendDetail, let backendButton {
            config = Config.load()
            let name = Cleaner.backendName(config: config)
            let hasBackend = Cleaner.backendAvailable(config: config)
            if hasBackend { ok(backendDetail, name) } else { wait(backendDetail, name) }
            backendButton.isEnabled = hasBackend
        }
        if let hotkeyDetail {
            let d = Trigger.from(config.triggerKey).label
            let r = Trigger.from(config.readKey).label
            let a = Trigger.from(config.assistantKey).label
            hotkeyDetail.stringValue = "• " + L.t(zh: "听写 \(d) · 朗读 \(r) · 语音助手 \(a)",
                                                  en: "Dictation \(d) · Read \(r) · Assistant \(a)")
            hotkeyDetail.textColor = .secondaryLabelColor
        }
        if remoteDetail != nil { updateRemoteStatus() }
        if let readDetail, let readButton {
            let rl = Trigger.from(config.readKey).label
            if Speaker.premiumVoices().isEmpty {
                wait(readDetail, L.t(zh: "未装高质量嗓音 → 点「下载语音」去系统设置下载",
                                     en: "No Enhanced/Premium voice — tap “Download” to get one"))
                readButton.title = L.t(zh: "下载语音", en: "Download")
            } else {
                let voiceLabel = config.readVoice.isEmpty
                    ? L.t(zh: "自动", en: "Auto")
                    : (AVSpeechSynthesisVoice(identifier: config.readVoice)?.name ?? config.readVoice)
                readDetail.stringValue = "• " + L.t(zh: "语音：\(voiceLabel) · 双击\(rl) 从选中处往下读",
                                                    en: "Voice: \(voiceLabel) · double-tap \(rl) to read")
                readDetail.textColor = .secondaryLabelColor
                readButton.title = L.t(zh: "设置", en: "Configure")
            }
        }
    }

    private func ok(_ f: NSTextField, _ s: String)   { f.stringValue = "✓ " + s; f.textColor = .systemGreen }
    private func bad(_ f: NSTextField, _ s: String)  { f.stringValue = "✗ " + s; f.textColor = .systemRed }
    private func wait(_ f: NSTextField, _ s: String) { f.stringValue = "• " + s; f.textColor = .secondaryLabelColor }

    // MARK: 动作

    @objc private func reqMic() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in DispatchQueue.main.async { self.refresh() } }
        } else { openSettings("Privacy_Microphone") }
    }

    @objc private func reqSpeech() {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { _ in DispatchQueue.main.async { self.refresh() } }
        } else { openSettings("Privacy_SpeechRecognition") }
    }

    @objc private func openAX() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        openSettings("Privacy_Accessibility")
    }

    @objc private func downloadModel() {
        guard let modelBar, let modelButton, let modelDetail else { return }
        modelBar.isHidden = false; modelBar.doubleValue = 0; modelButton.isHidden = true
        wait(modelDetail, L.t(zh: "准备下载…", en: "Preparing…"))
        ModelDownloader.shared.startDownload(progress: { [weak self] p, text in
            guard let self else { return }
            self.modelBar?.doubleValue = p
            self.modelDetail?.stringValue = "• " + text
        }, completion: { [weak self] success in
            guard let self else { return }
            if success { Whisper.startServer(); self.onModelReady?() }
            self.modelBar?.isHidden = true
            self.refresh()
        })
    }

    @objc private func testBackend() {
        guard let backendDetail, let backendButton else { return }
        backendButton.isEnabled = false
        wait(backendDetail, L.t(zh: "测试中…（首次启动 CLI 可能要几秒）", en: "Testing… (first CLI run takes a few seconds)"))
        let sample = L.t(zh: "呃那个我想说的就是说这个测试一下", en: "um so like i just wanted to uh test this")
        var cfg = Config.load(); cfg.cleanup = true
        Cleaner.clean(sample, config: cfg) { [weak self] result in
            guard let self, let backendDetail = self.backendDetail else { return }
            let name = Cleaner.backendName(config: cfg)
            self.ok(backendDetail, L.t(zh: "\(name) ✓ 「\(result)」", en: "\(name) ✓ \"\(result)\""))
            self.backendButton?.isEnabled = true
        }
    }

    @objc private func configureHotkey() { onConfigureHotkey?() }

    @objc private func readButtonTapped() {
        if Speaker.premiumVoices().isEmpty { openVoiceDownload() } else { onConfigureRead?() }
    }

    private func openVoiceDownload() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: 隐私政策（弹 sheet 展示全文，同意后解锁「下一步」）

    @objc private func openPolicy() {
        guard let window else { return }
        let W: CGFloat = 460, H: CGFloat = 520
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: H),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = L.t(zh: "隐私政策", en: "Privacy Policy")

        let root = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        let scroll = NSScrollView(frame: NSRect(x: 18, y: 60, width: W-36, height: H-78))
        scroll.hasVerticalScroller = true; scroll.borderType = .lineBorder; scroll.autohidesScrollers = true
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: W-36, height: H-78))
        tv.isEditable = false; tv.isSelectable = true
        tv.textContainerInset = NSSize(width: 14, height: 12); tv.font = .systemFont(ofSize: 12)
        tv.string = policyText()
        scroll.documentView = tv
        root.addSubview(scroll)

        let agree = NSButton(title: L.t(zh: "我已阅读，同意", en: "I've read and agree"),
                             target: self, action: #selector(agreePolicy))
        agree.bezelStyle = .rounded; agree.keyEquivalent = "\r"
        agree.frame = NSRect(x: W-18-156, y: 16, width: 156, height: 30)
        root.addSubview(agree)

        let cancel = NSButton(title: L.t(zh: "关闭", en: "Close"), target: self, action: #selector(closePolicy))
        cancel.bezelStyle = .rounded
        cancel.frame = NSRect(x: W-18-156-10-80, y: 16, width: 80, height: 30)
        root.addSubview(cancel)

        sheet.contentView = root
        policySheet = sheet
        window.beginSheet(sheet)
    }

    private var policySheet: NSWindow?

    @objc private func closePolicy() {
        if let s = policySheet { window?.endSheet(s); policySheet = nil }
    }

    @objc private func agreePolicy() {
        privacyAgreed = true
        try? FileManager.default.createDirectory(atPath: Config.dir, withIntermediateDirectories: true)
        try? "ok".write(toFile: Onboarding.privacyMarker, atomically: true, encoding: .utf8)
        consentStatus?.stringValue = "✓ " + L.t(zh: "已阅读并同意隐私政策", en: "Read and agreed")
        consentStatus?.textColor = .systemGreen
        updateNextGate()
        closePolicy()
    }

    private func policyText() -> String {
        L.t(zh: """
        Easylii 出品 · 生效 2026-06-17

        1. 语音转写（本机完成）：听写时音频在本地转成文字，只在转写那一刻留在内存，随后丢弃，绝不上传。

        2. 可选 AI 整理（用你自己的账号）：开启时仅把转写文字发到你配置的服务商（Anthropic / OpenAI），走你自己的 key 或订阅，不配置则不发送，可随时关闭。

        3. 我们不做的事：不在服务器收集 / 存储你的音频或文字；无分析、埋点、崩溃上报、追踪；无账号、无广告；不出售、不共享数据。

        4. 本机文件：设置、本地日志、上次转写结果都只存在你的 Mac（~/.config/siyu/），不会传给我们，可随时删除。

        5. macOS 权限：麦克风、语音识别、辅助功能，仅用于对应功能，可随时在系统设置撤销。

        6. 你的权利（GDPR / CCPA 等）：我们不持有你的个人数据，这边无可访问 / 删除项；你完全掌控本机数据。

        7. 联系：support@easylii.com
        """, en: """
        By Easylii · Effective June 17, 2026

        1. Voice transcription (on-device): audio becomes text locally, kept in memory only for the moment of transcription, then discarded. Never uploaded.

        2. Optional AI cleanup (your own account): when enabled, only the transcribed text is sent to the provider you configure (Anthropic / OpenAI) using your own key or subscription. If unset, nothing is sent. Optional.

        3. What we don't do: no collection/storage of your audio or text on any server; no analytics, telemetry, crash reporting, tracking; no accounts; no ads; we don't sell or share data.

        4. Local files: settings, a local log, and your last result live only on your Mac (~/.config/siyu/). Nothing is sent to us; delete anytime.

        5. macOS permissions: Microphone, Speech Recognition, Accessibility — used only for those functions, revocable anytime.

        6. Your rights (GDPR / CCPA): we hold no personal data about you; nothing on our side to access or delete. You control the local data.

        7. Contact: support@easylii.com
        """)
    }
}
