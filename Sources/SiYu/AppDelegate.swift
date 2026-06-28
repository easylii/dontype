import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let hotkey = HotkeyMonitor()
    private let readHotkey = HotkeyMonitor()   // 朗读选中文字的独立触发键
    private let assistantHotkey = HotkeyMonitor()   // 语音助手触发键（双击 = 对讲机）
    private let gamepad = GameControllerInput() // 蓝牙手柄：A 键听写、摇杆移光标、十字键方向键
    private let remote = RemoteHID()            // Apple TV 遥控器特殊键（id=251）：选择/方向/菜单…
    private let touchpad = MultitouchRemote()   // 遥控器触摸面 → 鼠标（私有 MultitouchSupport，可选）
    private var touchpadRetryTimer: Timer?      // 遥控器启动时若睡着，触摸面枚举不到 → 定时重试，醒了自动接管
    private var touchpadReattachWork: DispatchWorkItem?  // 遥控器重连后去抖重接触摸面
    private let dictation = Dictation()
    private let speaker = Speaker()
    private let hud = HUD()
    private var config = Config.load()
    private var statusItem: NSStatusItem!
    private var busy = false
    private var lastRemoteArrowAt: TimeInterval = 0   // 最近一次遥控器方向键导航的时刻（OK 用它和触摸板比，判断有没有高亮）
    private var lastOKAt: TimeInterval = 0            // 上次按 OK 的时刻（判 double-OK）
    private var lastPasteAt: TimeInterval = 0         // 最近一次听写粘贴的时刻（之后按 OK = 回车发送）
    private var readArmed = false                     // 刚 double-OK 选了文字 → 下次 TV 改成朗读
    private var readArmedAt: TimeInterval = 0

    /// 朗读设置（语音/语速/触发键/试听），从设置向导进入。
    private lazy var readSetup = ReadSetup(readHotkey: readHotkey, speaker: speaker) { [weak self] kv in
        self?.persist(kv)
    }

    /// 在线语音助手（Claude Code + 语音连续对话，plan 只读），单独 opt-in、走云端。
    private let voiceLoop = VoiceLoop(workdir: (("~/Documents/SiYu") as NSString).expandingTildeInPath)
    private let voiceOrb = VoiceOrb()
    /// 摄像头 + 本地实时追踪（Apple Vision：脸 / 手 / 身体），从菜单进入。
    private lazy var cameraWindow = CameraWindow()

    /// 遥控器设置（画出遥控器 + 实时点亮 + 每键分配动作 + 触摸板鼠标），从设置进入。
    private lazy var remoteSetup = RemoteSetup(remote: remote, touchpad: touchpad) { [weak self] kv in
        guard let self else { return }
        self.persist(kv)
        self.config = Config.load()   // 同步内存 config（含 remoteMap），动作查表才不过时
    }

    /// 统一热键面板：一张键盘管三个功能（听写 / 朗读 / 语音助手），点选功能再点键换键，改了即时生效。
    private lazy var hotkeyCenter = HotkeyCenter([
        .init(name: L.t(zh: "听写", en: "Dictation"),
              gesture: L.t(zh: "双击开始 · 单击结束 · Esc 不粘贴", en: "Double-tap to start · tap to stop · Esc = no paste"),
              color: .systemBlue,
              get: { [weak self] in self?.config.triggerKey ?? "control" },
              apply: { [weak self] id in
                  guard let self else { return }
                  self.config.triggerKey = id; self.persist(["triggerKey": id]); self.hotkey.setTrigger(.from(id))
                  self.statusItem.button?.toolTip = L.t(zh: "丝语 · 双击\(self.hotkey.trigger.label) 开始/结束",
                                                        en: "Dontype · double-tap \(self.hotkey.trigger.label) to start/stop")
                  self.rebuildMenu()
              }),
        .init(name: L.t(zh: "朗读", en: "Read aloud"),
              gesture: L.t(zh: "选中后双击朗读 · 单击暂停/继续 · Esc 停", en: "Select, double-tap to read · tap to pause · Esc to stop"),
              color: .systemGreen,
              get: { [weak self] in self?.config.readKey ?? "rightCommand" },
              apply: { [weak self] id in
                  guard let self else { return }
                  self.config.readKey = id; self.persist(["readKey": id]); self.readHotkey.setTrigger(.from(id)); self.rebuildMenu()
              }),
        .init(name: L.t(zh: "语音助手", en: "Assistant"),
              gesture: L.t(zh: "双击激活 · 单击 说/停发送/继续 · Esc 关闭", en: "Double-tap to start · tap to talk/send · Esc to close"),
              color: .systemOrange,
              get: { [weak self] in self?.config.assistantKey ?? "leftCommand" },
              apply: { [weak self] id in
                  guard let self else { return }
                  self.config.assistantKey = id; self.persist(["assistantKey": id]); self.assistantHotkey.setTrigger(.from(id)); self.rebuildMenu()
              }),
    ])

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
        Onboarding.shared.onConfigureHotkey = { [weak self] in self?.hotkeyCenter.show() }
        Onboarding.shared.onConfigureRead = { [weak self] in self?.readSetup.show() }
        Onboarding.shared.onConfigureRemote = { [weak self] in self?.remoteSetup.show() }
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
        Onboarding.shared.onChangeCleanupBackend = { [weak self] id in
            guard let self else { return }
            self.config.cleanupBackend = id
            self.persist(["cleanupBackend": id])
            self.rebuildMenu()   // 菜单里「AI 整理」那行同步显示新后端
        }
        Onboarding.shared.onChangeRemoteEnabled = { [weak self] on in
            guard let self else { return }
            self.config.remoteEnabled = on
            self.persist(["remoteEnabled": on])
            if on { self.touchpad.start(); self.enableFullKeyboardAccess() } else { self.touchpad.stop() }   // 触摸板鼠标随总开关
            self.rebuildMenu()
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
        // Esc：立刻取消 —— 关麦、丢弃、不转写不分析，回到待命等下一条命令
        hotkey.onEscape = { [weak self] in
            guard let self, self.dictation.isRecording else { return }
            self.cancelDictation()
        }
        hotkey.diagnostic = config.diagnostic   // 诊断模式：记录每个键到日志（测遥控器用）
        hotkey.start()

        // 蓝牙手柄：A 键切换听写、左摇杆移光标、十字键方向键、B 键点击（手柄连上即生效）
        gamepad.onToggleDictation = { [weak self] in self?.toggleDictation() }
        gamepad.start()

        // 语音助手：编排器 ↔ 状态球
        voiceLoop.onState = { [weak self] s in
            guard let self else { return }
            self.voiceOrb.setState(s)                                // 待命也留着球，关闭才隐藏
            // 激活后进入「轻点切换」：干净单击 = 切换对讲（不抢 ⌘ 快捷键，无需双击）；未激活时双击才激活。
            self.assistantHotkey.tapToggleMode = self.voiceLoop.active
            self.assistantHotkey.escActive = self.voiceLoop.active   // 激活期间 Esc 随时能关
        }
        voiceLoop.onLevel = { [weak self] lv in self?.voiceOrb.setLevel(lv) }
        voiceOrb.onStop = { [weak self] in self?.voiceLoop.stop(); self?.voiceOrb.hide(); self?.rebuildMenu() }

        // 语音助手键盘触发：双击 = 激活（并开始说）；激活后单击 = 切换（说 / 停发送 / 打断）；Esc = 关闭
        assistantHotkey.setTrigger(Trigger.from(config.assistantKey))
        assistantHotkey.onDoubleTap = { [weak self] in
            guard let self else { return }
            self.voiceOrb.show(); self.voiceLoop.beginTalk(); self.rebuildMenu()
        }
        assistantHotkey.onSingleTap = { [weak self] in self?.voiceLoop.talk() }   // 激活后：单击切换说/停发送/打断
        assistantHotkey.onEscape = { [weak self] in
            guard let self, self.voiceLoop.active else { return }
            self.voiceLoop.stop(); self.voiceOrb.hide(); self.rebuildMenu()
        }
        assistantHotkey.start()

        // Apple TV 遥控器特殊键（id=251）：按设置里的映射执行动作（默认 选择=听写、方向键=导航）。
        // 设置页打开时 remote.suppressed=true，只点亮不执行。需「输入监视」权限，有了才真正监听。
        remote.onButtonEdge = { [weak self] code, down in
            guard let self else { return }
            if down, self.config.diagnostic { FileLog.write("🎛 遥控键 \(code)（\(RemoteHID.id(forCode: code) ?? "?"))") }
            guard down, !self.remote.suppressed else { return }
            self.performRemoteAction(code)
        }
        remote.logAll = config.diagnostic   // 诊断时记录遥控器全部报文（查触摸面有没有发坐标）
        // 遥控器（重）连上 → 去抖后重新接管触摸面：断开重连后旧触摸面句柄失效，必须 stop+start 刷新
        remote.onAttached = { [weak self] in
            guard let self, self.config.remoteEnabled else { return }
            self.touchpadReattachWork?.cancel()
            let w = DispatchWorkItem { [weak self] in
                guard let self, self.config.remoteEnabled else { return }
                self.touchpad.stop(); self.touchpad.start()
            }
            self.touchpadReattachWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: w)
        }
        remote.start()

        // 遥控器触摸面当鼠标（私有 MultitouchSupport）——随总开关
        if config.remoteEnabled { touchpad.start(); enableFullKeyboardAccess() }
        // 启动时遥控器可能没醒（触摸面枚举不到）→ 每 3s 重试，遥控器一醒就自动接管；接管后 guard !running 变空操作
        touchpadRetryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, self.config.remoteEnabled, !self.touchpad.running else { return }
            self.touchpad.start()
        }

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
                    self.assistantHotkey.start()
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

    /// 一键切换听写：没在录就开始、正在录就结束并粘贴。遥控器/手柄共用。
    private func toggleDictation() {
        if dictation.isRecording { stopAndProcess(paste: true) } else { startRecording() }
    }

    /// 遥控器某键按下 → 按当前映射执行动作。总开关关了就不执行。
    private func performRemoteAction(_ code: String) {
        guard config.remoteEnabled else { return }
        let action = config.remoteMap[code] ?? RemoteHID.defaultAction(code)
        // 用了方向键导航 → 记下时刻；OK 时若比触摸板更近，就认「有高亮」、激活它而非点鼠标
        if ["up", "down", "left", "right", "tabNext", "tabPrev"].contains(action) {
            lastRemoteArrowAt = ProcessInfo.processInfo.systemUptime
            if config.diagnostic { logFocusDiag(action) }   // 诊断：按方向键那一刻焦点/光标状态
        }
        switch action {
        // TV 键上下文相关：朗读中 → 停；刚 double-OK 选了文字(12s 内) → 朗读这段；否则 → 听写
        case "dictation":
            if speaker.isSpeaking { stopReading() }
            else if readArmed, ProcessInfo.processInfo.systemUptime - readArmedAt < 12 {
                readArmed = false; startReading()
            } else { toggleDictation() }
        // 取消(返回 ‹)：助手对话中 → 关闭助手；听写中 → 立刻中止丢弃；朗读中 → 停止朗读；否则 → 发 Esc
        case "cancel":
            if voiceLoop.active { voiceLoop.stop(); voiceOrb.hide(); rebuildMenu() }
            else if dictation.isRecording { cancelDictation() }
            else if speaker.isSpeaking { stopReading() }
            else { postKey(53) }
        // 通用规范（不依赖读焦点，网页/原生都一致）：
        // 竖轴 ↑/↓ = 真方向键（列表/菜单/侧栏上下走）；横轴 ←/→ = Shift+Tab/Tab（在控件/按钮间跳）。
        case "up":        postArrow(126)   // ↑
        case "down":      postArrow(125)   // ↓
        case "left":      postTab(shift: true)    // ← = Shift+Tab 上一个控件
        case "right":     postTab(shift: false)   // → = Tab 下一个控件
        case "tabNext":   postTab(shift: false)
        case "tabPrev":   postTab(shift: true)
        case "click":
            if voiceLoop.active { voiceLoop.talk() }          // 语音助手中：OK 也当对讲机键用
            else { handleOK() }                               // 否则：单击=激活/点击；鼠标双击=选中这段
        case "readToggle":
            if speaker.isSpeaking { togglePauseReading() } else { startReading() }
        // 右侧键 = 对讲机：按一下开始说、再按一下停下并发送、它念时按=打断。关助手用菜单/点球。
        case "assistant": voiceOrb.show(); voiceLoop.talk(); rebuildMenu()
        default: break    // none
        }
    }

    /// 中间 OK：鼠标模式下「连按两下」= 在光标处三连击选中所在段落/行，并备好朗读（下次 TV 念这段）；
    /// 否则就是普通单次确认（postClickOrSend）。
    private func handleOK() {
        let now = ProcessInfo.processInfo.systemUptime
        let mouseMode = lastRemoteArrowAt <= MultitouchRemote.lastMoveUptime   // 指点状态才允许双击选字
        if mouseMode, now - lastOKAt < 0.45 {
            postMultiClick(3)                       // 三连击 → 选中所在这段文字
            readArmed = true; readArmedAt = now     // 下次按 TV 朗读这段
            lastOKAt = 0                            // 防止三连按再次触发
        } else {
            lastOKAt = now
            postClickOrSend()
        }
    }

    /// 中间键(OK)= 确认/激活。规则：优先「高亮项」，没有高亮才用「鼠标位置」。
    /// 怎么判断有没有高亮：方向键和触摸板谁最近被用就听谁的（都没动过 = 没高亮 → 鼠标）：
    ///  • 方向键更近（在控高亮）→ 激活高亮项：原生 App 读得到焦点就精准处理（输入框=回车、可按下控件=直接按下）；
    ///    网页/Electron 读不到焦点（恒 nil）→ 发回车，激活 Tab/方向键聚焦的那一项（等同点它）。
    ///  • 触摸板更近（在指鼠标）/ 从没导航 → 在光标处左键单击。
    private func postClickOrSend() {
        // 刚听写粘贴完（10s 内）或焦点就是输入框 → OK = 回车（把内容发出去）。
        // 网页/Electron 读不到焦点，就靠「刚粘贴过」这个信号兜底。
        if ProcessInfo.processInfo.systemUptime - lastPasteAt < 10
            || (focusedElement().map(isTextInput) ?? false) {
            postKey(36); return   // 36 = Return
        }
        let hasHighlight = lastRemoteArrowAt > MultitouchRemote.lastMoveUptime   // 方向键比触摸板更近 = 有高亮
        guard hasHighlight else { postClick(); return }                          // 没高亮 → 点鼠标光标处
        if let el = focusedElement() {                                           // 原生 App：直接激活聚焦的高亮控件
            if isTextInput(el) { postKey(36); return }   // 36 = Return（输入框=回车）
            if axPress(el) { return }                    // 可「按下」控件 → 直接激活
        }
        postKey(36)   // 网页/Electron 读不到焦点 → 回车激活高亮项
    }

    /// Tab / Shift+Tab：在控件/链接间跳焦点。统一走 postKey 的「网页直达进程」分流。
    private func postTab(shift: Bool) { postKey(48, flags: shift ? .maskShift : []) }

    /// 打开 macOS「键盘导航 / 全键盘访问」（AppleKeyboardUIMode），让 Tab/方向键能跳到按钮 ——
    /// 否则系统默认下 Tab 只在文本框/列表间跳，落不到按钮。幂等：已开就不动。
    /// 已经运行的 App 多数下次激活/启动时生效；设置持久化，之后一直有效。
    private func enableFullKeyboardAccess() {
        let key = "AppleKeyboardUIMode" as CFString
        let cur = (CFPreferencesCopyValue(key, kCFPreferencesAnyApplication,
                                          kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Int) ?? 0
        guard cur & 2 == 0 else { return }   // 值 2 那位 =「所有控件」，已开则跳过
        CFPreferencesSetValue(key, 3 as CFNumber, kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("AppleKeyboardUIModeChanged"), object: nil, deliverImmediately: true)
        FileLog.write("⌨︎ 已开启全键盘访问（AppleKeyboardUIMode=3）：Tab/方向键可跳到按钮")
    }

    /// 在当前光标位置合成一次鼠标左键单击（遥控器当鼠标时用）。
    private func postClick() { postMultiClick(1) }

    /// 在光标处合成 n 连击（clickState 1…n）：2 连击=选词、3 连击=选所在段落/行。
    private func postMultiClick(_ count: Int) {
        let p = CGEvent(source: nil)?.location ?? .zero
        for i in 1...max(1, count) {
            let down = CGEvent(mouseEventSource: arrowSource, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)
            down?.setIntegerValueField(.mouseEventClickState, value: Int64(i)); down?.post(tap: .cghidEventTap)
            let up = CGEvent(mouseEventSource: arrowSource, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)
            up?.setIntegerValueField(.mouseEventClickState, value: Int64(i)); up?.post(tap: .cghidEventTap)
        }
    }

    /// 合成一个键送到当前焦点目标 —— 关键修复：按目标分流投递路径。
    /// 网页/Electron（辅助功能读不到焦点，恒 nil）→ 直接投给前台 App 进程（postToPid），
    ///   绕开系统层（含全键盘访问）的拦截 —— 合成的 Tab 在 HID 层会被全键盘访问吃掉、网页 DOM 收不到，
    ///   物理 Tab 却能到，差别就在这；直达进程后网页就能正常收到 Tab/方向键/回车。
    /// 原生 App（读得到焦点）→ 走 HID 级，配合全键盘访问让 Tab 落到按钮。
    private func postKey(_ keycode: CGKeyCode, flags: CGEventFlags = []) {
        guard let down = CGEvent(keyboardEventSource: arrowSource, virtualKey: keycode, keyDown: true),
              let up = CGEvent(keyboardEventSource: arrowSource, virtualKey: keycode, keyDown: false) else { return }
        down.flags = flags; up.flags = flags
        if focusedElement() == nil, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            down.postToPid(pid); up.postToPid(pid)                         // 网页/Electron：直达进程
        } else {
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)   // 原生：HID 层（全键盘访问到按钮）
        }
    }

    /// 系统级当前键盘焦点元素。
    private func focusedElement() -> AXUIElement? {
        let sys = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let el = focused else { return nil }
        return (el as! AXUIElement)
    }

    /// 诊断：打印当前键盘焦点元素 —— 角色/子角色、所属 App、输入光标/选区、字段内容长度。
    /// 用来看「在 text field 里听写完按右键」那一刻，焦点还在不在输入框、光标在哪。
    private func logFocusDiag(_ tag: String) {
        guard let el = focusedElement() else {
            FileLog.write("🎯 [\(tag)] 焦点=nil —— AX 读不到聚焦元素（多半是网页/Electron，未桥接辅助功能）")
            return
        }
        func str(_ a: String) -> String {
            var r: CFTypeRef?; AXUIElementCopyAttributeValue(el, a as CFString, &r); return (r as? String) ?? "-"
        }
        var pid: pid_t = 0; AXUIElementGetPid(el, &pid)
        let app = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?(pid \(pid))"
        var cursor = "-"
        var rv: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &rv) == .success,
           let v = rv, CFGetTypeID(v) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(v as! AXValue, .cfRange, &range) { cursor = "loc=\(range.location) len=\(range.length)" }
        }
        let val = str(kAXValueAttribute as String)
        let valLen = val == "-" ? -1 : val.count
        FileLog.write("🎯 [\(tag)] @\(app) role=\(str(kAXRoleAttribute as String))/\(str(kAXSubroleAttribute as String)) "
                      + "光标[\(cursor)] 字段长=\(valLen) 文本输入框=\(isTextInput(el))")
    }

    /// 焦点是否是「文本输入框」（决定 OK 发回车还是别的）。
    private func isTextInput(_ el: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleRef as? String) ?? ""
        if role == (kAXTextFieldRole as String) || role == (kAXTextAreaRole as String) { return true }
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(el, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue {
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valueRef) == .success,
               valueRef is String { return true }
        }
        return false
    }

    /// 聚焦控件支持「按下」动作(按钮/链接等) → 直接激活，返回是否成功。
    private func axPress(_ el: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(el, &names) == .success,
              let arr = names as? [String], arr.contains(kAXPressAction as String) else { return false }
        return AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
    }

    private let arrowSource = CGEventSource(stateID: .hidSystemState)
    /// 合成一次方向键（按下+抬起），发给当前前台 App。
    private func postArrow(_ keycode: CGKeyCode) { postKey(keycode) }

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
    /// 取消听写：立刻关麦、丢弃录音，不转写、不做 AI 分析，回到待命（Esc / 遥控器返回 ‹）。
    private func cancelDictation() {
        guard dictation.isRecording else { return }
        dictation.cancel()
        hotkey.recordingActive = false
        setIcon(.idle)
        hud.showCancelled()
    }

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
                FileLog.write("整理后：「\(final.prefix(100))」")   // 对照原始转写，查清洗有没有改飞
                let doPaste = paste && self.config.autoPaste
                if doPaste {
                    Paster.paste(final)   // paste 内部会先写剪贴板
                    self.lastPasteAt = ProcessInfo.processInfo.systemUptime   // 之后按 OK = 回车发送
                }
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
                self.speaker.speak(text, voiceID: self.config.readVoice, lang: self.config.readLang, rate: self.config.readRate)
                self.readHotkey.recordingActive = true
                self.hud.showSpeaking(paused: false, under: self.statusItemScreenRect())
                FileLog.write("朗读开始（\(text.count) 字）：「\(text.prefix(120))」")   // 记内容：定位是抓错还是念飞
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

        // 三个「模式」各自一个二级子菜单：图标 + 名字 ▸，提示/开关都收进去，风格统一
        menu.addItem(modeItem(L.t(zh: "听写 · 说话 → 文字", en: "Dictation · speech → text"),
                              symbol: "waveform", build: buildDictationSubmenu))
        menu.addItem(modeItem(L.t(zh: "朗读 · 文字 → 说话", en: "Read aloud · text → speech"),
                              symbol: "speaker.wave.2.fill", build: buildReadSubmenu))
        menu.addItem(modeItem(voiceLoop.active ? L.t(zh: "语音助手 · 对话中", en: "Voice assistant · active")
                                               : L.t(zh: "语音助手 · 在线对话", en: "Voice assistant · online"),
                              image: AssistantIcon.image(), build: buildAssistantSubmenu))

        let camera = NSMenuItem(title: L.t(zh: "摄像头 · 追踪（脸 / 手 / 身体）", en: "Camera · tracking (face / hands / body)"),
                                action: #selector(openCamera), keyEquivalent: "")
        camera.image = NSImage(systemSymbolName: "video", accessibilityDescription: nil)
        camera.target = self
        menu.addItem(camera)

        menu.addItem(.separator())

        // 剪贴历史：顶层平铺，点一下复制回剪贴板（不放二级菜单）
        buildRecallItems().forEach { menu.addItem($0) }

        menu.addItem(.separator())

        let setup = NSMenuItem(title: L.t(zh: "设置向导…", en: "Setup Wizard…"),
                               action: #selector(openOnboarding), keyEquivalent: "")
        setup.target = self
        menu.addItem(setup)

        let quit = NSMenuItem(title: L.t(zh: "退出丝语", en: "Quit Dontype"),
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    /// 顶层「模式」项：SF Symbol 图标 + 名字，挂一个用 build 填充的二级子菜单。
    private func modeItem(_ title: String, symbol: String, build: (NSMenu) -> Void) -> NSMenuItem {
        modeItem(title, image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil), build: build)
    }
    private func modeItem(_ title: String, image: NSImage?, build: (NSMenu) -> Void) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.image = image
        let sub = NSMenu(); build(sub); it.submenu = sub
        return it
    }

    /// 听写子菜单：用法提示 + AI 整理/自动粘贴开关 + 麦克风 + 遥控器提示。
    private func buildDictationSubmenu(_ m: NSMenu) {
        m.addItem(hintItem(L.t(zh: "双击 \(hotkey.trigger.label) 开始 · 单击结束 · Esc 不粘贴",
                               en: "Double-tap \(hotkey.trigger.label) to start · tap to stop · Esc = no paste")))
        m.addItem(.separator())
        let cleanup = NSMenuItem(title: L.t(zh: "停用 AI 整理（默认：自动）", en: "Disable AI cleanup (default: auto)"),
                                 action: #selector(toggleCleanup), keyEquivalent: "")
        cleanup.target = self; cleanup.state = config.cleanup ? .off : .on
        m.addItem(cleanup)
        let paste = NSMenuItem(title: L.t(zh: "自动粘贴到光标", en: "Auto-paste at cursor"),
                               action: #selector(toggleAutoPaste), keyEquivalent: "")
        paste.target = self; paste.state = config.autoPaste ? .on : .off
        m.addItem(paste)
        m.addItem(buildMicMenu())
        m.addItem(.separator())
        m.addItem(hintItem(L.t(zh: "遥控器：TV 说话 · 再按完成 · ‹/Esc 取消 · ↑↓ 列表 · ←→ Tab 切控件",
                               en: "Remote: TV talks · again finishes · ‹/Esc cancels · ↑↓ lists · ←→ Tab")))
    }

    /// 朗读子菜单：用法提示。
    private func buildReadSubmenu(_ m: NSMenu) {
        m.addItem(hintItem(L.t(zh: "选中后双击 \(Trigger.from(config.readKey).label) 朗读 · 单击暂停/继续 · Esc 停",
                               en: "Select, double-tap \(Trigger.from(config.readKey).label) to read · tap to pause · Esc to stop")))
        m.addItem(hintItem(L.t(zh: "纯文本上双击 OK 选中这段 → 按 TV 朗读（再按停）",
                               en: "On plain text: double-tap OK to select → TV reads it (TV again stops)")))
    }

    /// 语音助手子菜单：启停动作 + 用法提示 + 在线说明。
    private func buildAssistantSubmenu(_ m: NSMenu) {
        let toggle = NSMenuItem(title: voiceLoop.active ? L.t(zh: "停止语音助手", en: "Stop voice assistant")
                                                        : L.t(zh: "启动语音助手", en: "Start voice assistant"),
                                action: #selector(openAssistant), keyEquivalent: "")
        toggle.target = self
        m.addItem(toggle)
        m.addItem(.separator())
        m.addItem(hintItem(L.t(zh: "双击 \(Trigger.from(config.assistantKey).label) 进入对话 · 张嘴就说、停下自动接 · 单击打断 · Esc 关闭",
                               en: "Double-tap \(Trigger.from(config.assistantKey).label) to enter · just talk, pause to send · tap to interrupt · Esc to close")))
        m.addItem(hintItem(L.t(zh: "连续对话 · 在线 · 走 Claude Code · plan 只读", en: "Continuous · online · via Claude Code · plan read-only")))
        m.addItem(.separator())
        m.addItem(hintItem(L.t(zh: "对话模型", en: "Model")))
        for (id, name) in [("haiku", L.t(zh: "Haiku · 最快", en: "Haiku · fastest")),
                           ("sonnet", L.t(zh: "Sonnet · 均衡", en: "Sonnet · balanced")),
                           ("opus", L.t(zh: "Opus · 最强", en: "Opus · strongest"))] {
            let it = NSMenuItem(title: name, action: #selector(setAssistantModel(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = id
            it.state = (config.assistantModel == id) ? .on : .off
            m.addItem(it)
        }
    }

    @objc private func setAssistantModel(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        config.assistantModel = id
        persist(["assistantModel": id])
        voiceLoop.resetAssistant()   // 下次开口用新模型重启会话
        rebuildMenu()
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

    /// 遥控键 id → 媒体键码（NX_KEYTYPE_*）；"off"/未知 = nil（关闭）。
    static func remoteMediaCode(_ id: String) -> Int64? {
        switch id {
        case "playpause": return 16
        case "mute":      return 7
        case "next":      return 17
        case "prev":      return 18
        default:          return nil
        }
    }

    /// 当前遥控器用什么键触发听写：媒体键优先，否则取 id=251 里映射到「听写」的那个键。空 = 没设。
    private func remoteDictationTriggerLabel() -> String {
        let media: [String: String] = [
            "playpause": L.t(zh: "播放/暂停", en: "Play/Pause"), "mute": L.t(zh: "静音", en: "Mute"),
            "prev": L.t(zh: "上一首", en: "Prev"), "next": L.t(zh: "下一首", en: "Next"),
        ]
        if config.remoteKey != "off", let n = media[config.remoteKey] { return n }
        for b in RemoteHID.buttons where (config.remoteMap[b.code] ?? RemoteHID.defaultAction(b.code)) == "dictation" {
            return L.t(zh: b.zh, en: b.en)
        }
        return ""
    }

    @objc private func recallEntry(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        RecallStore.shared.recall(byText: text)   // 复制回剪贴板并置顶；自己 Cmd+V 粘到想要的地方
        FileLog.write("剪贴历史重取 → 已复制（\(text.count) 字）")
    }

    @objc private func openRemoteSetup() { remoteSetup.show() }

    @objc private func openCamera() { cameraWindow.show() }

    /// 菜单开/关语音助手：开 → 显示状态球、进入「待命」（用右侧键说话）；再点 → 关。
    @objc private func openAssistant() {
        if voiceLoop.active { voiceLoop.stop(); voiceOrb.hide() }
        else { voiceOrb.show(); voiceLoop.open() }
        rebuildMenu()
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
