import AppKit
import WebKit
import Foundation

/// Apple TV 遥控器页（连接感知）：
/// 没连 → 显示「未连接」+ 配对引导（唤醒 / 打开蓝牙）；连了 → 授权 + 两个标签页：
///   「用法演示」= 4 步循环 SVG 动画；「按键映射」= 静态遥控器图 + 实时感知（按物理键点亮）+ 每键分配动作。
/// 连接状态用 system_profiler 异步查（不需要任何权限）。映射期间 remote.suppressed=true，只点亮不执行。
final class RemoteSetup: NSObject, NSWindowDelegate {
    private let remote: RemoteHID
    private let touchpad: MultitouchRemote
    private let persist: ([String: Any]) -> Void

    init(remote: RemoteHID, touchpad: MultitouchRemote, persist: @escaping ([String: Any]) -> Void) {
        self.remote = remote
        self.touchpad = touchpad
        self.persist = persist
    }

    private var window: NSWindow?
    private var statusLabel: NSTextField!
    private var guideBox: NSStackView!
    private var usageBox: NSStackView!
    private var accessLabel: NSTextField!
    private var accessButton: NSButton!
    private var accessRow: NSStackView!
    private var connTimer: Timer?
    private var accessTimer: Timer?
    private var connected = false

    // 映射页：实时感知 + 每键分配动作
    private var mapWeb: WKWebView?                       // 静态遥控器 SVG（按物理键点亮）
    private var rowViews: [String: NSView] = [:]         // 键码 → 行容器（按下时高亮）
    private var popups: [String: NSPopUpButton] = [:]    // 键码 → 动作下拉
    private var remoteMap: [String: String] = [:]        // 当前映射（code → action），改了即时持久化

    func show() {
        remoteMap = Config.load().remoteMap            // 进来先拿当前映射
        if window == nil { build() }
        remote.start()
        remote.suppressed = true                       // 配置期间：按键只点亮、不执行动作
        remote.onState = { [weak self] pressed in self?.applyPressed(pressed) }
        syncPopups()                                   // 下拉按当前映射回填
        startTimers()
        NSApp.activate(ignoringOtherApps: true)
        window?.center(); window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        connTimer?.invalidate(); connTimer = nil
        accessTimer?.invalidate(); accessTimer = nil
        remote.onState = nil                           // 放开感知，恢复正常执行
        remote.suppressed = false
        rowViews.values.forEach { $0.layer?.backgroundColor = NSColor.clear.cgColor }
    }

    // MARK: 状态轮询

    private func startTimers() {
        refreshAccess(); checkConnection()
        accessTimer?.invalidate()
        accessTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.refreshAccess() }
        connTimer?.invalidate()
        connTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in self?.checkConnection() }
    }

    /// 异步查蓝牙：Apple TV Remote 是否在「已连接」里。
    private func checkConnection() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let on = RemoteSetup.remoteIsConnected()
            DispatchQueue.main.async { self?.applyConnection(on) }
        }
    }

    private func applyConnection(_ on: Bool) {
        connected = on
        guideBox.isHidden = on
        usageBox.isHidden = !on
        if on {
            statusLabel.stringValue = "✓ " + L.t(zh: "遥控器已连接", en: "Remote connected")
            statusLabel.textColor = .systemGreen
        } else {
            statusLabel.stringValue = "○ " + L.t(zh: "遥控器未连接", en: "Remote not connected")
            statusLabel.textColor = .secondaryLabelColor
        }
        window?.layoutIfNeeded()
    }

    /// 跑 system_profiler 解析「已连接」列表里有没有遥控器。
    private static func remoteIsConnected() -> Bool {
        let task = Process()
        task.launchPath = "/usr/sbin/system_profiler"
        task.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = Pipe()
        do { try task.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let arr = json["SPBluetoothDataType"] as? [[String: Any]], let bt = arr.first,
              let conn = bt["device_connected"] as? [[String: Any]] else { return false }
        return conn.contains { dict in dict.keys.contains { $0.localizedCaseInsensitiveContains("Remote") } }
    }

    // MARK: 输入监视权限（连接后才需要）

    private func refreshAccess() {
        guard accessRow != nil else { return }
        if RemoteHID.hasAccess {
            accessRow.isHidden = true          // 已授权就别再占一行（连接状态那行已是绿勾）
            if !remote.isRunning { remote.start() }
        } else {
            accessRow.isHidden = false
            accessLabel.stringValue = "• " + L.t(zh: "点「授权」开启输入监视才能读按键", en: "Grant Input Monitoring to read the keys")
            accessLabel.textColor = .secondaryLabelColor
            accessButton.isHidden = false
        }
    }

    @objc private func grantAccess() {
        RemoteHID.requestAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openBluetooth() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func done() { window?.close() }

    // MARK: UI

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L.t(zh: "丝语 · 遥控器", en: "Dontype · Remote")
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.delegate = self

        let root = NSStackView()
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 16, right: 22)
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: L.t(zh: "Apple TV 遥控器", en: "Apple TV Remote"))
        title.font = .boldSystemFont(ofSize: 15)
        root.addArrangedSubview(title)

        statusLabel = NSTextField(labelWithString: "…")
        statusLabel.font = .systemFont(ofSize: 13)
        root.addArrangedSubview(statusLabel)

        root.addArrangedSubview(buildGuideBox())
        root.addArrangedSubview(buildUsageBox())

        let doneBtn = NSButton(title: L.t(zh: "完成", en: "Done"), target: self, action: #selector(done))
        doneBtn.bezelStyle = .rounded; doneBtn.keyEquivalent = "\r"
        let footer = NSStackView(views: [NSView(), doneBtn])
        footer.orientation = .horizontal
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.widthAnchor.constraint(equalToConstant: 520).isActive = true
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
        w.setContentSize(NSSize(width: 564, height: 540))
        window = w
    }

    /// 未连接：配对 / 唤醒引导。
    private func buildGuideBox() -> NSStackView {
        let box = NSStackView()
        box.orientation = .vertical; box.alignment = .leading; box.spacing = 10
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 496).isActive = true

        let steps = NSTextField(wrappingLabelWithString:
            L.t(zh: "遥控器没连上(可能睡着了)。这样连:\n"
                  + "  1. 拿起遥控器,按任意键唤醒 → 通常会自动重连\n"
                  + "  2. 还没连上 → 打开蓝牙设置,在列表里点 “Apple TV Remote” 连接\n"
                  + "  3. 列表里都没有(首次配对)→ 把遥控器靠近 Mac,按住「返回 ‹ + 音量＋」约 5 秒",
                en: "Remote isn't connected (it may be asleep):\n"
                  + "  1. Pick it up and press any key to wake it — it usually reconnects.\n"
                  + "  2. Still not connected → open Bluetooth and click “Apple TV Remote”.\n"
                  + "  3. Not in the list (first pairing) → hold Back ‹ + Volume + near the Mac for ~5s."))
        steps.font = .systemFont(ofSize: 12); steps.textColor = .secondaryLabelColor
        steps.preferredMaxLayoutWidth = 496
        box.addArrangedSubview(steps)

        let btBtn = NSButton(title: L.t(zh: "打开蓝牙设置", en: "Open Bluetooth Settings"),
                             target: self, action: #selector(openBluetooth))
        btBtn.bezelStyle = .rounded
        box.addArrangedSubview(btBtn)

        guideBox = box
        return box
    }

    /// 已连接：授权行 + 标签页（用法演示 / 按键映射）。
    private func buildUsageBox() -> NSStackView {
        let box = NSStackView()
        box.orientation = .vertical; box.alignment = .leading; box.spacing = 12
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 520).isActive = true

        accessLabel = NSTextField(labelWithString: "…")
        accessLabel.font = .systemFont(ofSize: 12)
        accessButton = NSButton(title: L.t(zh: "授权", en: "Grant"), target: self, action: #selector(grantAccess))
        accessButton.bezelStyle = .rounded
        accessRow = NSStackView(views: [accessLabel, accessButton])
        accessRow.orientation = .horizontal; accessRow.spacing = 10; accessRow.alignment = .centerY
        box.addArrangedSubview(accessRow)

        let tabs = NSTabView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.widthAnchor.constraint(equalToConstant: 520).isActive = true
        tabs.heightAnchor.constraint(equalToConstant: 380).isActive = true

        // 用法演示（保留原来的 4 步循环动画）
        let demo = NSTabViewItem(identifier: "demo")
        demo.label = L.t(zh: "用法演示", en: "Demo")
        let demoWeb = WKWebView(frame: .zero)
        demoWeb.wantsLayer = true; demoWeb.layer?.cornerRadius = 10; demoWeb.layer?.masksToBounds = true
        demoWeb.loadHTMLString(RemoteSetup.demoHTML(), baseURL: nil)
        let demoHost = NSView()
        demoWeb.translatesAutoresizingMaskIntoConstraints = false
        demoHost.addSubview(demoWeb)
        NSLayoutConstraint.activate([
            demoWeb.leadingAnchor.constraint(equalTo: demoHost.leadingAnchor, constant: 4),
            demoWeb.trailingAnchor.constraint(equalTo: demoHost.trailingAnchor, constant: -4),
            demoWeb.topAnchor.constraint(equalTo: demoHost.topAnchor, constant: 4),
            demoWeb.heightAnchor.constraint(equalToConstant: 250),
        ])
        demo.view = demoHost
        tabs.addTabViewItem(demo)

        // 按键映射（实时感知 + 每键分配）
        let map = NSTabViewItem(identifier: "map")
        map.label = L.t(zh: "按键映射", en: "Mapping")
        map.view = buildMapBox()
        tabs.addTabViewItem(map)

        box.addArrangedSubview(tabs)
        usageBox = box
        return box
    }

    /// 映射页：左 = 静态遥控器 SVG（按物理键点亮）；右 = 每键一行（名字 + 动作下拉，可滚动）。
    private func buildMapBox() -> NSView {
        let host = NSView()

        let web = WKWebView(frame: .zero)
        web.wantsLayer = true; web.layer?.cornerRadius = 10; web.layer?.masksToBounds = true
        web.translatesAutoresizingMaskIntoConstraints = false
        web.loadHTMLString(RemoteSetup.mapHTML(), baseURL: nil)
        mapWeb = web
        host.addSubview(web)

        let rows = NSStackView()
        rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 5
        rows.translatesAutoresizingMaskIntoConstraints = false
        let hint = NSTextField(wrappingLabelWithString: L.t(
            zh: "按遥控器上的某个键 → 它在左图和这一行都会亮 → 在它的下拉里选动作（即时生效）。",
            en: "Press a key on the remote → it lights up on the left and its row → pick its action (applies live)."))
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 322
        rows.addArrangedSubview(hint)
        for b in RemoteHID.buttons { rows.addArrangedSubview(makeRow(b)) }

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.documentView = rows
        host.addSubview(scroll)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: scroll.contentView.topAnchor, constant: 2),
            rows.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor, constant: 2),
            rows.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor, constant: -4),

            web.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 6),
            web.topAnchor.constraint(equalTo: host.topAnchor, constant: 6),
            web.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -6),
            web.widthAnchor.constraint(equalToConstant: 150),
            scroll.leadingAnchor.constraint(equalTo: web.trailingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: host.topAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -6),
        ])
        return host
    }

    /// 一行：键名 + 动作下拉。容器存进 rowViews 以便按下时高亮。
    private func makeRow(_ b: RemoteHID.Btn) -> NSView {
        let row = NSView()
        row.wantsLayer = true; row.layer?.cornerRadius = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        rowViews[b.code] = row

        let name = NSTextField(labelWithString: L.t(zh: b.zh, en: b.en))
        name.font = .systemFont(ofSize: 12)
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false

        let pop = NSPopUpButton(frame: .zero, pullsDown: false)
        pop.translatesAutoresizingMaskIntoConstraints = false
        for a in RemoteHID.actions { pop.addItem(withTitle: L.t(zh: a.zh, en: a.en)) }
        pop.identifier = NSUserInterfaceItemIdentifier(b.code)
        pop.target = self; pop.action = #selector(mapActionChanged(_:))
        popups[b.code] = pop

        row.addSubview(name); row.addSubview(pop)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 30),
            row.widthAnchor.constraint(equalToConstant: 322),
            name.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 6),
            name.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            name.widthAnchor.constraint(equalToConstant: 116),
            pop.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 6),
            pop.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -6),
            pop.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    /// 下拉按当前映射回填（跟默认相同的就显示默认项）。
    private func syncPopups() {
        for b in RemoteHID.buttons {
            let action = remoteMap[b.code] ?? b.def
            if let idx = RemoteHID.actions.firstIndex(where: { $0.id == action }) {
                popups[b.code]?.selectItem(at: idx)
            }
        }
    }

    @objc private func mapActionChanged(_ sender: NSPopUpButton) {
        guard let code = sender.identifier?.rawValue else { return }
        let action = RemoteHID.actions[max(0, sender.indexOfSelectedItem)].id
        if action == RemoteHID.defaultAction(code) { remoteMap.removeValue(forKey: code) }  // 同默认就不存
        else { remoteMap[code] = action }
        persist(["remoteMap": remoteMap])   // AppDelegate 落盘并重载内存 config，动作即时生效
    }

    /// 实时感知：按住的键 → 左图点亮 + 对应行高亮（suppressed 期间不执行动作）。
    private func applyPressed(_ pressed: Set<String>) {
        for b in RemoteHID.buttons {
            let on = pressed.contains(b.code)
            rowViews[b.code]?.layer?.backgroundColor = on
                ? NSColor.systemGreen.withAlphaComponent(0.30).cgColor : NSColor.clear.cgColor
            if let id = RemoteHID.id(forCode: b.code) {
                mapWeb?.evaluateJavaScript("hl('\(id)',\(on))", completionHandler: nil)
            }
        }
    }

    /// 4 步循环动画（双语）：按 TV 说话 → 再按出文字 → Esc/返回 取消 → 触摸板移光标。真实 Siri Remote。
    private static func demoHTML() -> String {
        let p1t = L.t(zh: "按一次 TV 键", en: "Press TV once")
        let p1s = L.t(zh: "开始说话 · 出现声波", en: "Start talking · waveform")
        let p2t = L.t(zh: "再按一次 TV 键", en: "Press TV again")
        let p2s = L.t(zh: "完成 · 文字出现", en: "Done · text appears")
        let p3t = L.t(zh: "Esc / 返回键 ‹", en: "Esc / Back ‹")
        let p3s = L.t(zh: "取消 · 不粘贴", en: "Cancel · no paste")
        let p4t = L.t(zh: "触摸板滑动", en: "Swipe the touchpad")
        let p4s = L.t(zh: "移动鼠标光标", en: "Move the mouse cursor")
        let typed = RemoteSetup.typedTextSVG(L.t(zh: "你好世界", en: "Hello"))
        return """
    <!doctype html><meta charset="utf-8">
    <style>
      :root{ --btn:#1b1b1d; --on:#34d399; --accent:#3b9eff; --txt:#e6e8ee; --dim:#8b93a3; --ic:#cfd2d7; }
      html,body{ margin:0; height:100%; background:#171a21; color:var(--txt);
        font:13px/1.5 -apple-system,"SF Pro Rounded",system-ui,sans-serif; -webkit-font-smoothing:antialiased; }
      .card{ position:relative; overflow:hidden; height:100vh; }   /* 遥控器贴底、底部沉到边外被裁 */
      svg{ position:absolute; left:26px; top:14px; width:200px; height:auto; display:block; }
      #tv{ animation:hlTV 16s infinite; } #back{ animation:hlBk 16s infinite; } #pad{ animation:hlPad 16s infinite; }
      @keyframes hlTV{ 0%,2%{fill:var(--btn)} 4%,21%{fill:var(--on)} 24%,28%{fill:var(--btn)} 30%,47%{fill:var(--on)} 50%,100%{fill:var(--btn)} }
      @keyframes hlBk{ 0%,52%{fill:var(--btn)} 55%,72%{fill:var(--on)} 75%,100%{fill:var(--btn)} }
      @keyframes hlPad{ 0%,77%{stroke:#1b1b1d;stroke-width:0} 80%,97%{stroke:var(--accent);stroke-width:1.4} 99%,100%{stroke:#1b1b1d;stroke-width:0} }
      #screen{ opacity:0; animation:sc 16s infinite; }   /* 小屏全程亮：依次 声波→文字→划掉→光标 */
      @keyframes sc{ 0%{opacity:0} 3%,98%{opacity:1} 99%,100%{opacity:0} }
      #wave{ opacity:0; animation:wv 16s infinite; }
      @keyframes wv{ 0%{opacity:0} 4%,22%{opacity:1} 25%,100%{opacity:0} }
      .bars{ transform-box:view-box; transform-origin:81px 23px; animation:pulse .5s ease-in-out infinite alternate; }
      @keyframes pulse{ from{transform:scaleY(.5)} to{transform:scaleY(1)} }
      /* 第二次按 TV：文字逐字打出（按语言动态生成 #chN + 关键帧） */
      \(typed.css)
      #xmark{ opacity:0; animation:xm 16s infinite; }   /* 取消：✕ 药丸 */
      @keyframes xm{ 0%,54%{opacity:0} 58%,72%{opacity:1} 74%,100%{opacity:0} }
      #finger,#cursor{ opacity:0; transform-box:fill-box; transform-origin:center; }
      #finger{ animation:fg 16s infinite; } #cursor{ animation:cs 16s infinite; }
      @keyframes fg{ 0%,77%{opacity:0;transform:translate(0,0)} 79%{opacity:.9;transform:translate(0,0)}
        84%{transform:translate(5px,-4px)} 89%{transform:translate(-4px,-2.5px)}
        94%{transform:translate(4px,4px)} 97%{opacity:.9;transform:translate(0,0)} 99%,100%{opacity:0} }
      @keyframes cs{ 0%,77%{opacity:0;transform:translate(0,0)} 79%{opacity:1;transform:translate(0,0)}
        84%{transform:translate(8px,-5px)} 89%{transform:translate(-7px,-3px)}
        94%{transform:translate(6px,5px)} 97%{opacity:1;transform:translate(0,0)} 99%,100%{opacity:0} }
      .caps{ position:absolute; left:250px; top:0; bottom:0; right:14px; }
      .cap{ position:absolute; top:50%; transform:translateY(-50%); opacity:0; }   /* 右侧竖直居中 */
      .cap b{ color:#fff; font-size:15px; } .cap .sub{ color:var(--dim); font-size:12px; }
      .badge{ display:inline-block; min-width:26px;height:26px;line-height:26px;text-align:center;padding:0 5px;
        background:var(--on);color:#06281c;border-radius:8px;font-weight:700;margin-right:8px;vertical-align:middle; }
      .badge.esc{ background:#3a3d42;color:#e6e8ee;font-size:11px; }
      #p1{ animation:s1 16s infinite } #p2{ animation:s2 16s infinite }
      #p3{ animation:s3 16s infinite } #p4{ animation:s4 16s infinite }
      @keyframes s1{ 0%{opacity:0} 4%,22%{opacity:1} 25%,100%{opacity:0} }
      @keyframes s2{ 0%,27%{opacity:0} 30%,47%{opacity:1} 50%,100%{opacity:0} }
      @keyframes s3{ 0%,52%{opacity:0} 55%,72%{opacity:1} 75%,100%{opacity:0} }
      @keyframes s4{ 0%,77%{opacity:0} 80%,97%{opacity:1} 99%,100%{opacity:0} }
    </style>
    <div class="card">
      <svg viewBox="33 0 64 100" xmlns="http://www.w3.org/2000/svg">
        <defs><linearGradient id="bodyG" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stop-color="#eceef1"/><stop offset="1" stop-color="#c4c8cf"/></linearGradient></defs>
        <rect x="37.03" y="3.15" width="24.83" height="94.18" rx="5" fill="url(#bodyG)" stroke="#aab0b8" stroke-width="0.4"/>
        <rect x="48.4" y="6.6" width="2.1" height="0.8" rx="0.4" fill="#3a3d42"/>
        <circle cx="56.64" cy="8.15" r="2.3" fill="var(--btn)"/>
        <path d="M56.64 7.45 v0.85 M55.99 7.95 a0.82 0.82 0 1 0 1.3 0" fill="none" stroke="var(--ic)" stroke-width="0.32" stroke-linecap="round"/>
        <circle id="pad" cx="49.44" cy="23" r="10.94" fill="var(--btn)"/>
        <circle id="center" cx="49.44" cy="23" r="6.33" fill="#2a2a2c"/>
        <g fill="#5a5c60"><circle cx="49.44" cy="14.6" r="0.55"/><circle cx="49.44" cy="31.4" r="0.55"/>
          <circle cx="41" cy="23" r="0.55"/><circle cx="57.9" cy="23" r="0.55"/></g>
        <circle id="back" cx="44.28" cy="38.75" r="4.5" fill="var(--btn)"/>
        <g transform="translate(39.48,33.95) scale(0.40)"><path d="M15 6l-6 6l6 6" fill="none" stroke="var(--ic)" stroke-width="0.9" vector-effect="non-scaling-stroke" stroke-linecap="round" stroke-linejoin="round"/></g>
        <circle id="tv" cx="54.6" cy="38.75" r="4.5" fill="var(--btn)"/>
        <g transform="translate(51.0,35.0) scale(0.30)" fill="none" stroke="var(--ic)" stroke-width="0.9" vector-effect="non-scaling-stroke" stroke-linecap="round" stroke-linejoin="round">
          <path d="M3 19l18 0"/>
          <path d="M5 7a1 1 0 0 1 1 -1h12a1 1 0 0 1 1 1v8a1 1 0 0 1 -1 1h-12a1 1 0 0 1 -1 -1l0 -8"/></g>
        <circle cx="44.28" cy="48.9" r="4.5" fill="var(--btn)"/>
        <g transform="translate(40.68,45.3) scale(0.30)"><path d="M15 5V19M21 5V19M3 7.20608V16.7939C3 17.7996 3 18.3024 3.19886 18.5352C3.37141 18.7373 3.63025 18.8445 3.89512 18.8236C4.20038 18.7996 4.55593 18.4441 5.26704 17.733L10.061 12.939C10.3897 12.6103 10.554 12.446 10.6156 12.2565C10.6697 12.0898 10.6697 11.9102 10.6156 11.7435C10.554 11.554 10.3897 11.3897 10.061 11.061L5.26704 6.26704C4.55593 5.55593 4.20038 5.20038 3.89512 5.17636C3.63025 5.15551 3.37141 5.26273 3.19886 5.46476C3 5.69759 3 6.20042 3 7.20608Z" fill="none" stroke="var(--ic)" stroke-width="0.9" vector-effect="non-scaling-stroke" stroke-linecap="round" stroke-linejoin="round"/></g>
        <rect x="50.1" y="44.4" width="9" height="18.65" rx="4.5" fill="var(--btn)"/>
        <path d="M54.6 47.2 v2.6 M53.3 48.5 h2.6" stroke="var(--ic)" stroke-width="0.55" stroke-linecap="round"/>
        <path d="M53.3 58 h2.6" stroke="var(--ic)" stroke-width="0.55" stroke-linecap="round"/>
        <circle cx="44.28" cy="59.05" r="4.5" fill="var(--btn)"/>
        <g transform="translate(40.92,55.69) scale(0.28)" fill="none" stroke="var(--ic)" stroke-width="0.9" vector-effect="non-scaling-stroke" stroke-linecap="round" stroke-linejoin="round">
          <path d="M15 8a5 5 0 0 1 1.912 4.934m-1.377 2.602a5 5 0 0 1 -.535 .464"/>
          <path d="M17.7 5a9 9 0 0 1 2.362 11.086m-1.676 2.299a9 9 0 0 1 -.686 .615"/>
          <path d="M9.069 5.054l.431 -.554a.8 .8 0 0 1 1.5 .5v2m0 4v8a.8 .8 0 0 1 -1.5 .5l-3.5 -4.5h-2a1 1 0 0 1 -1 -1v-4a1 1 0 0 1 1 -1h2l1.294 -1.664"/>
          <path d="M3 3l18 18"/>
        </g>
        <circle id="finger" cx="49.44" cy="23" r="2.6" fill="#ffffffcc"/>
        <rect id="screen" x="69" y="14" width="26" height="18" rx="2" fill="#11151c" stroke="#2a2e38" stroke-width="0.4"/>
        <g id="wave"><g class="bars" fill="#34d399">
          <rect x="74.4" y="20.5" width="1.6" height="5" rx="0.8"/>
          <rect x="77.6" y="18.5" width="1.6" height="9" rx="0.8"/>
          <rect x="80.8" y="16.5" width="1.6" height="13" rx="0.8"/>
          <rect x="84.0" y="19" width="1.6" height="8" rx="0.8"/>
          <rect x="87.2" y="20.5" width="1.6" height="5" rx="0.8"/>
        </g></g>
        \(typed.svg)
        <g id="xmark">
          <circle cx="82" cy="23" r="6.6" fill="#3a1414" stroke="#ff6b6b" stroke-width="0.6"/>
          <path d="M79.2 20.2 l5.6 5.6 M84.8 20.2 l-5.6 5.6" stroke="#ff6b6b" stroke-width="1.3" stroke-linecap="round"/>
        </g>
        <path id="cursor" d="M78 19 l0 4.3 l1.1 -1.1 l0.9 1.7 l0.8 -0.3 l-0.9 -1.7 l1.7 0 z" fill="#fff"/>
      </svg>
      <div class="caps">
        <div class="cap" id="p1"><div><span class="badge">TV</span><b>\(p1t)</b></div><div class="sub">\(p1s)</div></div>
        <div class="cap" id="p2"><div><span class="badge">TV</span><b>\(p2t)</b></div><div class="sub">\(p2s)</div></div>
        <div class="cap" id="p3"><div><span class="badge esc">esc</span><b>\(p3t)</b></div><div class="sub">\(p3s)</div></div>
        <div class="cap" id="p4"><div><span class="badge">🖱</span><b>\(p4t)</b></div><div class="sub">\(p4s)</div></div>
      </div>
    </div>
    """
    }

    /// 映射页用的「静态遥控器」SVG：每个可分配键带 id（= RemoteHID 的 id），hl(id,on) 切换高亮。
    /// 触摸板：中心=select，四向小点=up/down/left/right；back=menu、tv=tv、侧条=side、顶=power、下方两键=b3/b4、音量条=bar。
    private static func mapHTML() -> String {
        return """
    <!doctype html><meta charset="utf-8">
    <style>
      html,body{ margin:0; height:100%; background:#171a21; }
      svg{ display:block; width:100%; height:100%; }
      .btn{ fill:#1b1b1d; } .ic{ stroke:#cfd2d7; fill:none; }
      .dot{ fill:#5a5c60; } .on{ fill:#34d399 !important; }
    </style>
    <svg viewBox="34 0 62 100" xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMidYMid meet">
      <defs><linearGradient id="bodyG" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#eceef1"/><stop offset="1" stop-color="#c4c8cf"/></linearGradient></defs>
      <rect x="37.03" y="3.15" width="24.83" height="94.18" rx="5" fill="url(#bodyG)" stroke="#aab0b8" stroke-width="0.4"/>
      <rect x="48.4" y="6.6" width="2.1" height="0.8" rx="0.4" fill="#3a3d42"/>
      <circle id="power" class="btn" cx="56.64" cy="8.15" r="2.3"/>
      <path d="M56.64 7.45 v0.85 M55.99 7.95 a0.82 0.82 0 1 0 1.3 0" class="ic" stroke-width="0.32" stroke-linecap="round"/>
      <rect id="side" class="btn" x="61.0" y="26" width="1.7" height="10" rx="0.85"/>
      <circle cx="49.44" cy="23" r="10.94" fill="#1b1b1d"/>
      <circle id="select" class="btn" cx="49.44" cy="23" r="6.33" style="fill:#2a2a2c"/>
      <circle id="up"    class="dot" cx="49.44" cy="14.6" r="1.2"/>
      <circle id="down"  class="dot" cx="49.44" cy="31.4" r="1.2"/>
      <circle id="left"  class="dot" cx="41"    cy="23"   r="1.2"/>
      <circle id="right" class="dot" cx="57.9"  cy="23"   r="1.2"/>
      <circle id="menu" class="btn" cx="44.28" cy="38.75" r="4.5"/>
      <g transform="translate(39.48,33.95) scale(0.40)"><path d="M15 6l-6 6l6 6" class="ic" stroke-width="0.9" vector-effect="non-scaling-stroke" stroke-linecap="round" stroke-linejoin="round"/></g>
      <circle id="tv" class="btn" cx="54.6" cy="38.75" r="4.5"/>
      <g transform="translate(51.0,35.0) scale(0.30)" class="ic" stroke-width="0.9" vector-effect="non-scaling-stroke" stroke-linecap="round" stroke-linejoin="round">
        <path d="M3 19l18 0"/>
        <path d="M5 7a1 1 0 0 1 1 -1h12a1 1 0 0 1 1 1v8a1 1 0 0 1 -1 1h-12a1 1 0 0 1 -1 -1l0 -8"/></g>
      <circle id="b3" class="btn" cx="44.28" cy="48.9" r="4.5"/>
      <g transform="translate(40.68,45.3) scale(0.30)"><path d="M15 5V19M21 5V19M3 7.20608V16.7939C3 17.7996 3 18.3024 3.19886 18.5352C3.37141 18.7373 3.63025 18.8445 3.89512 18.8236C4.20038 18.7996 4.55593 18.4441 5.26704 17.733L10.061 12.939C10.3897 12.6103 10.554 12.446 10.6156 12.2565C10.6697 12.0898 10.6697 11.9102 10.6156 11.7435C10.554 11.554 10.3897 11.3897 10.061 11.061L5.26704 6.26704C4.55593 5.55593 4.20038 5.20038 3.89512 5.17636C3.63025 5.15551 3.37141 5.26273 3.19886 5.46476C3 5.69759 3 6.20042 3 7.20608Z" class="ic" stroke-width="0.9" vector-effect="non-scaling-stroke" stroke-linecap="round" stroke-linejoin="round"/></g>
      <rect id="bar" class="btn" x="50.1" y="44.4" width="9" height="18.65" rx="4.5"/>
      <path d="M54.6 47.2 v2.6 M53.3 48.5 h2.6 M53.3 58 h2.6" class="ic" stroke-width="0.55" stroke-linecap="round"/>
      <circle id="b4" class="btn" cx="44.28" cy="59.05" r="4.5"/>
      <g transform="translate(40.92,55.69) scale(0.28)" class="ic" stroke-width="0.9" vector-effect="non-scaling-stroke" stroke-linecap="round" stroke-linejoin="round">
        <path d="M15 8a5 5 0 0 1 1.912 4.934m-1.377 2.602a5 5 0 0 1 -.535 .464"/>
        <path d="M17.7 5a9 9 0 0 1 2.362 11.086m-1.676 2.299a9 9 0 0 1 -.686 .615"/>
        <path d="M9.069 5.054l.431 -.554a.8 .8 0 0 1 1.5 .5v2m0 4v8a.8 .8 0 0 1 -1.5 .5l-3.5 -4.5h-2a1 1 0 0 1 -1 -1v-4a1 1 0 0 1 1 -1h2l1.294 -1.664"/>
        <path d="M3 3l18 18"/></g>
    </svg>
    <script>function hl(id,on){var e=document.getElementById(id);if(e)e.classList.toggle('on',on);}</script>
    """
    }

    /// 把一段文字做成小屏里的「逐字打出」动画：每字一个 <text> + 错开淡入关键帧（中英都适配）。
    private static func typedTextSVG(_ s: String) -> (svg: String, css: String) {
        let chars = Array(s)
        let n = max(chars.count, 1)
        let fs = 5.6
        let isCJK = s.unicodeScalars.contains { $0.value >= 0x3000 && $0.value <= 0x9FFF }
        let adv = isCJK ? fs : fs * 0.58          // 汉字全角、拉丁窄一些
        let startX = 82.0 - adv * Double(n - 1) / 2.0
        var svg = "<g font-size=\"\(fs)\" text-anchor=\"middle\" fill=\"#e6e8ee\" font-family=\"-apple-system,sans-serif\">"
        var css = ""
        for (i, ch) in chars.enumerated() {
            let x = startX + adv * Double(i)
            let on = min(32 + i * 3, 47)           // 每字错开 3%，像打字；封顶 47% 落在第二步内
            svg += "<text id=\"ch\(i)\" x=\"\(String(format: "%.1f", x))\" y=\"25.4\" style=\"opacity:0\">\(ch)</text>"
            css += "#ch\(i){animation:chk\(i) 16s infinite}@keyframes chk\(i){0%,\(on)%{opacity:0}\(on+2)%,50%{opacity:1}53%,100%{opacity:0}}"
        }
        svg += "</g>"
        return (svg, css)
    }
}
