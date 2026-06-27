import AppKit
import Vision

/// 自定义手势能映射到的动作。isHold = 保持手势时持续触发（如滚动）；否则识别到的那一下触发一次。
enum GestureAction: String, CaseIterable, Codable {
    case none, leftClick, rightClick, scrollUp, scrollDown, escape, spaceKey
    var isHold: Bool { self == .scrollUp || self == .scrollDown }
    var label: String {
        switch self {
        case .none:       return L.t(zh: "（无）", en: "None")
        case .leftClick:  return L.t(zh: "左键单击", en: "Left click")
        case .rightClick: return L.t(zh: "右键单击", en: "Right click")
        case .scrollUp:   return L.t(zh: "向上滚动", en: "Scroll up")
        case .scrollDown: return L.t(zh: "向下滚动", en: "Scroll down")
        case .escape:     return L.t(zh: "Esc", en: "Esc")
        case .spaceKey:   return L.t(zh: "空格", en: "Space")
        }
    }
}

/// 一个学到的静态手势：名字 + 动作 + 若干「归一化关键点特征」样本。
struct CustomGesture: Codable {
    var name: String
    var action: GestureAction
    var samples: [[Double]]      // 每个样本 = 42 维特征
}

/// 手势库：特征提取（21 关键点平移到手腕 + 按手掌尺度缩放）、最近邻识别、训练加样本、JSON 持久化。
final class GestureLibrary {
    private(set) var gestures: [CustomGesture] = []
    var threshold = 0.55         // 最近邻距离阈值：越小越严
    private let path = (("~/.config/siyu/gestures.json") as NSString).expandingTildeInPath

    static let joints: [VNHumanHandPoseObservation.JointName] = [
        .wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip,
    ]

    init() { load() }

    /// 手部观测 → 42 维归一化特征（位置/大小无关，保留朝向）。缺手腕/中指根 → nil。
    static func feature(_ hand: VNHumanHandPoseObservation) -> [Double]? {
        guard let pts = try? hand.recognizedPoints(.all),
              let w = pts[.wrist], let mid = pts[.middleMCP] else { return nil }
        let scale = max(1e-4, Double(hypot(mid.location.x - w.location.x, mid.location.y - w.location.y)))
        var f = [Double]()
        for j in joints {
            let p = pts[j]
            f.append(Double((p?.location.x ?? w.location.x) - w.location.x) / scale)
            f.append(Double((p?.location.y ?? w.location.y) - w.location.y) / scale)
        }
        return f
    }

    private static func dist(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return .infinity }
        var s = 0.0; for i in a.indices { let d = a[i] - b[i]; s += d * d }
        return (s / Double(a.count)).squareRoot()
    }

    /// 单帧最近邻识别：返回（手势, 距离）里距离最近的；调用方再按阈值判定。
    func bestMatch(_ hand: VNHumanHandPoseObservation) -> (CustomGesture, Double)? {
        guard let f = GestureLibrary.feature(hand) else { return nil }
        var best: (CustomGesture, Double)?
        for g in gestures {
            let d = g.samples.map { GestureLibrary.dist(f, $0) }.min() ?? .infinity
            if best == nil || d < best!.1 { best = (g, d) }
        }
        return best
    }

    func recognize(_ hand: VNHumanHandPoseObservation) -> CustomGesture? {
        guard let (g, d) = bestMatch(hand), d < threshold else { return nil }
        return g
    }

    // MARK: 训练 / 编辑

    func addSamples(name: String, action: GestureAction, features: [[Double]]) {
        if let i = gestures.firstIndex(where: { $0.name == name }) {
            gestures[i].samples.append(contentsOf: features)
            gestures[i].action = action
        } else {
            gestures.append(CustomGesture(name: name, action: action, samples: features))
        }
        save()
    }
    func setAction(_ name: String, _ action: GestureAction) {
        if let i = gestures.firstIndex(where: { $0.name == name }) { gestures[i].action = action; save() }
    }
    func remove(_ name: String) { gestures.removeAll { $0.name == name }; save() }

    private func load() {
        guard let data = FileManager.default.contents(atPath: path),
              let g = try? JSONDecoder().decode([CustomGesture].self, from: data) else { return }
        gestures = g
    }
    private func save() {
        guard let data = try? JSONEncoder().encode(gestures) else { return }
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

/// 实时识别 + 触发动作：去抖（稳定 3 帧）→ edge 动作触发一次、hold 动作（滚动）每帧触发。
final class GestureRecognizer {
    let library = GestureLibrary()
    var enabled = false
    var onName: ((String?) -> Void)?     // 当前稳定识别到的手势名（给 UI 显示）

    private var lastName: String?
    private var streak = 0
    private var active: String?          // 当前已稳定生效的手势

    func process(_ hands: [VNHumanHandPoseObservation]) {
        guard enabled else { return }
        let hit = hands.first.flatMap { library.recognize($0) }
        let name = hit?.name
        if name == lastName { streak += 1 } else { lastName = name; streak = 1 }
        guard streak >= 3 else { return }            // 稳定 3 帧才算

        if name != active {                          // 切换 → edge 动作触发一次
            active = name
            onName?(name)
            if let hit, !hit.action.isHold { fire(hit.action) }
        }
        if let hit, hit.action.isHold, name == active { fire(hit.action) }   // hold → 每帧触发
    }

    private func fire(_ a: GestureAction) {
        let at = CGEvent(source: nil)?.location ?? .zero
        switch a {
        case .none: break
        case .leftClick:
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: at, mouseButton: .left)?.post(tap: .cghidEventTap)
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: at, mouseButton: .left)?.post(tap: .cghidEventTap)
        case .rightClick:
            CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: at, mouseButton: .right)?.post(tap: .cghidEventTap)
            CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: at, mouseButton: .right)?.post(tap: .cghidEventTap)
        case .scrollUp:
            CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
        case .scrollDown:
            CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -3, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
        case .escape:  postKey(53)
        case .spaceKey: postKey(49)
        }
    }
    private func postKey(_ code: CGKeyCode) {
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
    }
}

/// 训练窗口：列出已学手势（名字·动作·样本数·删除）；起名 + 选动作 + 「录制」。
/// 实际抓帧由摄像头窗负责（它有实时手部数据），这里只发起录制 + 展示。
final class GestureTrainerWindow: NSObject, NSWindowDelegate {
    private let library: GestureLibrary
    var onStartRecord: ((String, GestureAction) -> Void)?
    init(library: GestureLibrary) { self.library = library }

    private var window: NSWindow?
    private var listStack: NSStackView!
    private var nameField: NSTextField!
    private var actionPopup: NSPopUpButton!
    private let actions = GestureAction.allCases

    func show() {
        if window == nil { build() }
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.center(); window?.makeKeyAndOrderFront(nil)
    }

    @objc private func record() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        onStartRecord?(name, actions[max(0, actionPopup.indexOfSelectedItem)])
    }
    @objc private func removeSender(_ s: NSButton) {
        if let name = s.identifier?.rawValue { library.remove(name); refresh() }
    }
    @objc private func done() { window?.close() }

    func refresh() {
        guard let listStack else { return }
        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if library.gestures.isEmpty {
            let none = NSTextField(labelWithString: L.t(zh: "还没有手势。下面起名 → 选动作 → 录制（对着摄像头保持手势约 1 秒）。",
                                                        en: "No gestures yet. Name → action → Record (hold the pose ~1s)."))
            none.font = .systemFont(ofSize: 12); none.textColor = .secondaryLabelColor
            listStack.addArrangedSubview(none)
        }
        for g in library.gestures {
            let lbl = NSTextField(labelWithString: "\(g.name)　→　\(g.action.label)　·　\(g.samples.count)")
            lbl.font = .systemFont(ofSize: 13)
            let del = NSButton(title: L.t(zh: "删除", en: "Delete"), target: self, action: #selector(removeSender(_:)))
            del.bezelStyle = .rounded; del.identifier = NSUserInterfaceItemIdentifier(g.name)
            let row = NSStackView(views: [lbl, NSView(), del])
            row.orientation = .horizontal; row.alignment = .centerY
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: 392).isActive = true
            listStack.addArrangedSubview(row)
        }
    }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L.t(zh: "丝语 · 训练手势", en: "Dontype · Train Gestures")
        w.isReleasedWhenClosed = false; w.level = .floating; w.delegate = self

        let root = NSStackView()
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 24, bottom: 18, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: L.t(zh: "自定义手势", en: "Custom gestures"))
        title.font = .boldSystemFont(ofSize: 15)
        root.addArrangedSubview(title)

        listStack = NSStackView()
        listStack.orientation = .vertical; listStack.alignment = .leading; listStack.spacing = 6
        listStack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.borderType = .bezelBorder
        scroll.documentView = listStack
        scroll.widthAnchor.constraint(equalToConstant: 392).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 200).isActive = true
        NSLayoutConstraint.activate([
            listStack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor, constant: 6),
            listStack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor, constant: 6),
        ])
        root.addArrangedSubview(scroll)

        // 学习新手势：名字 + 动作 + 录制
        nameField = NSTextField(string: "")
        nameField.placeholderString = L.t(zh: "手势名（如 滚动）", en: "Name (e.g. scroll)")
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 150).isActive = true
        actionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for a in actions { actionPopup.addItem(withTitle: a.label) }
        let recBtn = NSButton(title: L.t(zh: "录制", en: "Record"), target: self, action: #selector(record))
        recBtn.bezelStyle = .rounded; recBtn.keyEquivalent = "\r"
        let addRow = NSStackView(views: [nameField, actionPopup, recBtn])
        addRow.orientation = .horizontal; addRow.spacing = 8; addRow.alignment = .centerY
        root.addArrangedSubview(addRow)

        let hint = NSTextField(wrappingLabelWithString: L.t(
            zh: "录制时：对着摄像头保持这个手势约 1 秒。想更准就同一个名字多录几次。识别需在摄像头窗勾选「手势识别」。",
            en: "While recording, hold the pose ~1s. Record the same name a few times for accuracy. Enable “Gesture recognition” in the camera window."))
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 392
        root.addArrangedSubview(hint)

        let doneBtn = NSButton(title: L.t(zh: "完成", en: "Done"), target: self, action: #selector(done))
        doneBtn.bezelStyle = .rounded
        let footer = NSStackView(views: [NSView(), doneBtn]); footer.orientation = .horizontal
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.widthAnchor.constraint(equalToConstant: 392).isActive = true
        root.addArrangedSubview(footer)

        let content = NSView(); content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        w.contentView = content
        w.setContentSize(NSSize(width: 440, height: content.fittingSize.height))
        window = w
    }
}
