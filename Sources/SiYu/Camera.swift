import AppKit
import AVFoundation
import Vision

/// 摄像头 + 本地实时追踪（Apple Vision，全在设备上跑、不上云）：
/// 抓每一帧 → 跑三个 Vision 请求（脸部关键点 / 手势 / 身体姿态）→ 回调最新结果。
/// CameraWindow 负责画实时预览 + 关键点叠加。这是「摄像头」功能的第一版（预览 + 追踪），动作控制以后再加。
final class CameraTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "siyu.camera.tracker")
    private var running = false
    private var currentInput: AVCaptureDeviceInput?
    private(set) var currentDeviceID: String?

    /// 可用摄像头：内置(MacBook) + 外接(USB/摄像头) + 连续互通(iPhone)。
    static func cameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
                                         mediaType: .video, position: .unspecified).devices
    }

    struct Results {
        var faces: [VNFaceObservation] = []
        var hands: [VNHumanHandPoseObservation] = []
        var bodies: [VNHumanBodyPoseObservation] = []
    }
    var onResults: ((Results) -> Void)?
    var onStatus: ((String) -> Void)?

    /// 请求摄像头权限后启动会话（幂等）。
    func start() {
        guard !running else { return }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
            DispatchQueue.main.async {
                guard let self else { return }
                guard ok else { self.onStatus?("缺摄像头权限 —— 去 系统设置 ▸ 隐私与安全性 ▸ 摄像头 勾选 Dontype"); return }
                self.configureAndRun()
            }
        }
    }

    private func configureAndRun() {
        guard !running else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        output.setSampleBufferDelegate(self, queue: queue)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        running = true
        // 默认优先内置(MacBook)；记住上次选的
        let cams = CameraTracker.cameras()
        let prefer = UserDefaults.standard.string(forKey: "cameraDeviceID")
        let dev = cams.first { $0.uniqueID == prefer }
            ?? cams.first { $0.deviceType == .builtInWideAngleCamera }
            ?? AVCaptureDevice.default(for: .video) ?? cams.first
        guard let dev else { onStatus?("找不到摄像头"); return }
        use(dev)
        queue.async { self.session.startRunning() }
    }

    /// 切换到指定摄像头（运行中也可切）；不镜像输出，叠加层才对齐。记住选择。
    func use(_ device: AVCaptureDevice) {
        guard let input = try? AVCaptureDeviceInput(device: device) else { onStatus?("无法打开：\(device.localizedName)"); return }
        session.beginConfiguration()
        if let ci = currentInput { session.removeInput(ci) }
        if session.canAddInput(input) { session.addInput(input); currentInput = input; currentDeviceID = device.uniqueID }
        if let conn = output.connection(with: .video) { conn.isVideoMirrored = false }
        session.commitConfiguration()
        UserDefaults.standard.set(device.uniqueID, forKey: "cameraDeviceID")
        onStatus?("摄像头：\(device.localizedName)")
        FileLog.write("📷 摄像头：\(device.localizedName)")
    }

    func stop() {
        guard running else { return }
        running = false
        queue.async { self.session.stopRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up, options: [:])
        let faceReq = VNDetectFaceLandmarksRequest()
        let handReq = VNDetectHumanHandPoseRequest(); handReq.maximumHandCount = 2
        let bodyReq = VNDetectHumanBodyPoseRequest()
        do { try handler.perform([faceReq, handReq, bodyReq]) } catch { return }
        var r = Results()
        r.faces = faceReq.results ?? []
        r.hands = handReq.results ?? []
        r.bodies = bodyReq.results ?? []
        DispatchQueue.main.async { self.onResults?(r) }
    }
}

/// One-Euro 滤波器：手部追踪治抖的标准做法 —— 慢动作强平滑、快动作低延迟，不像固定低通那样要么抖要么拖。
struct OneEuroFilter {
    var minCutoff = 0.5, beta = 0.2, dCutoff = 1.0   // minCutoff 小=静止更平滑；beta 小=快速移动不被噪声带飞
    private var xPrev: Double?, dxPrev = 0.0, tPrev = 0.0
    private func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1.0 / (2 * .pi * cutoff); return 1.0 / (1.0 + tau / dt)
    }
    mutating func filter(_ x: Double, _ t: Double) -> Double {
        guard let xp = xPrev else { xPrev = x; tPrev = t; return x }
        let dt = max(1e-3, t - tPrev)
        let dx = (x - xp) / dt
        let aD = alpha(dCutoff, dt)
        let edx = aD * dx + (1 - aD) * dxPrev
        let aC = alpha(minCutoff + beta * abs(edx), dt)
        let ex = aC * x + (1 - aC) * xp
        xPrev = ex; dxPrev = edx; tPrev = t
        return ex
    }
    mutating func reset() { xPrev = nil; dxPrev = 0 }
}

/// 手势控制鼠标（Phase 1）：食指指尖相对移动光标（隔空触控板）；拇指+食指捏合 = 按下/拖动/松开。
/// 相对映射 + 低通平滑 + 死区 + 捏合滞回；只在「启用」时接管。需辅助功能权限（App 已有）。
final class HandGestureController {
    var enabled = false { didSet { if enabled != oldValue { enabled ? begin() : end() } } }
    var onPinch: ((Bool) -> Void)?
    var activeMargin: Double = 0.15   // 画面四周留边；中间 (1-2*margin) 的区域线性映射到整个桌面

    private var filterX = OneEuroFilter()        // One-Euro 平滑食指位置，治抖
    private var filterY = OneEuroFilter()
    private var lastIndex: CGPoint?
    private var smoothRatio: Double = -1          // 捏合比例的低通
    private var smoothSpeed: Double = -1          // 手的移动速度（低通）—— 移动中不许按下
    private var armed = false                     // 「上膛」：手张开过才允许下一次按下，防半握移动误触
    private var pinching = false
    private var pinchStreak = 0                   // 连续几帧想翻转 → 去抖
    private var pinchAnchor: CGPoint?             // 按下点：捏合时先冻结在这，点击落点才稳
    private var dragging = false                  // 移动超过阈值才进入拖动
    private var cursor: CGPoint = .zero           // 全局 CGEvent 坐标（左上原点，跨所有屏）
    private var deskBounds: CGRect = .zero        // 所有显示器并集（CGEvent 坐标）

    /// 所有显示器并集 —— CGDisplayBounds 本就是 CGEvent 的全局坐标系，用它钳位才能跨屏。
    private func desktopBounds() -> CGRect {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        var r = CGRect.null
        for id in ids { r = r.union(CGDisplayBounds(id)) }
        return r.isNull ? (NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)) : r
    }

    private func begin() {
        cursor = CGEvent(source: nil)?.location ?? .zero   // 当前光标（全局 CGEvent 坐标）
        deskBounds = desktopBounds()
        filterX.reset(); filterY.reset(); lastIndex = nil
        smoothRatio = -1; smoothSpeed = -1; armed = false; pinching = false; pinchStreak = 0
        pinchAnchor = nil; dragging = false
    }
    private func end() {
        if pinching { post(.leftMouseUp); pinching = false; onPinch?(false) }
    }

    func process(_ hands: [VNHumanHandPoseObservation]) {
        guard enabled else { return }
        guard let hand = hands.first,
              let idx = try? hand.recognizedPoint(.indexTip), idx.confidence > 0.5,
              let thumb = try? hand.recognizedPoint(.thumbTip), thumb.confidence > 0.4,
              let wrist = try? hand.recognizedPoint(.wrist),
              let mcp = try? hand.recognizedPoint(.middleMCP) else {
            if pinching { post(.leftMouseUp); pinching = false; pinchStreak = 0; onPinch?(false) }  // 手丢了：松开，别卡在拖动
            filterX.reset(); filterY.reset(); lastIndex = nil; smoothSpeed = -1; armed = false
            pinchAnchor = nil; dragging = false
            return
        }
        let t = ProcessInfo.processInfo.systemUptime
        // 限速去瞬跳：一帧位移超过 maxStep 视为误检/瞬跳，按最大步长追过去（不瞬移）
        var inp = idx.location
        if let l = lastIndex {
            let d = hypot(inp.x - l.x, inp.y - l.y), maxStep: CGFloat = 0.12
            if d > maxStep { inp = CGPoint(x: l.x + (inp.x - l.x) / d * maxStep, y: l.y + (inp.y - l.y) / d * maxStep) }
        }
        let s = CGPoint(x: CGFloat(filterX.filter(Double(inp.x), t)),
                        y: CGFloat(filterY.filter(Double(inp.y), t)))
        defer { lastIndex = s }

        guard let last = lastIndex else { smoothRatio = -1; smoothSpeed = -1; return }   // 第一帧只记位置
        let mdx = s.x - last.x, mdy = s.y - last.y
        let speed = Double(hypot(mdx, mdy))
        smoothSpeed = smoothSpeed < 0 ? speed : (smoothSpeed * 0.6 + speed * 0.4)

        // 捏合：比例 = 拇指-食指距 / 手掌尺度（缩放无关）→ 低通。
        // 防误触：① 手要先张开(>0.7)「上膛」② 仅在手基本静止时(速度<0.012)才允许按下 ③ 连续 2 帧去抖。
        let span = Double(max(0.0001, hypot(wrist.location.x - mcp.location.x, wrist.location.y - mcp.location.y)))
        let rawRatio = Double(hypot(thumb.location.x - idx.location.x, thumb.location.y - idx.location.y)) / span
        smoothRatio = smoothRatio < 0 ? rawRatio : (smoothRatio * 0.6 + rawRatio * 0.4)
        if smoothRatio > 0.7 { armed = true }
        let want = pinching ? (smoothRatio < 0.6)
                            : (armed && smoothRatio < 0.36 && smoothSpeed < 0.012)
        if want != pinching {
            pinchStreak += 1
            if pinchStreak >= 2 {
                pinching = want; pinchStreak = 0
                if pinching { armed = false; pinchAnchor = cursor; dragging = false }  // 按下：卸膛 + 记按下点
                else { pinchAnchor = nil; dragging = false }
                post(pinching ? .leftMouseDown : .leftMouseUp); onPinch?(pinching)
            }
        } else { pinchStreak = 0 }

        // 绝对线性映射：手在画面中央子区域的位置 → 整个桌面对应位置（按桌面范围二次换算）。前置镜像翻 X、图像翻 Y。
        let inner = 1 - 2 * activeMargin
        let fx = min(1, max(0, (Double(1 - s.x) - activeMargin) / inner))
        let fy = min(1, max(0, (Double(1 - s.y) - activeMargin) / inner))
        let target = CGPoint(x: deskBounds.minX + CGFloat(fx) * deskBounds.width,
                             y: deskBounds.minY + CGFloat(fy) * deskBounds.height)
        // 捏合时先冻结在按下点（点击落点稳、不误拖）；移动超过 30px 才进入拖动
        if pinching, let a = pinchAnchor, !dragging {
            if hypot(target.x - a.x, target.y - a.y) > 30 { dragging = true; cursor = target }
            else { cursor = a }
        } else {
            cursor = target
        }
        post(pinching ? .leftMouseDragged : .mouseMoved)
    }

    private func post(_ type: CGEventType) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: cursor, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
}

/// 摄像头窗口：实时预览 + 脸/手/身体关键点叠加 + 三个显示开关 + 手势控制开关。
final class CameraWindow: NSObject, NSWindowDelegate {
    private let tracker = CameraTracker()
    private let gesture = HandGestureController()
    private var window: NSWindow?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var overlay: TrackingOverlayView?
    private var statusLabel: NSTextField!
    private var camName = ""
    private var cameraPopup: NSPopUpButton!
    private var cameraList: [AVCaptureDevice] = []

    func show() {
        if window == nil { build() }
        tracker.onStatus = { [weak self] s in self?.camName = s; self?.refreshStatus() }
        tracker.onResults = { [weak self] r in
            self?.overlay?.update(r)
            self?.gesture.process(r.hands)
        }
        gesture.onPinch = { [weak self] _ in self?.refreshStatus() }
        tracker.start()
        NSApp.activate(ignoringOtherApps: true)
        window?.center(); window?.makeKeyAndOrderFront(nil)
    }

    private func refreshStatus() {
        if gesture.enabled {
            statusLabel.stringValue = "🖐 " + L.t(zh: "手势控制中 · 食指移光标 · 捏合点击/拖动", en: "Gesture control on · index moves cursor · pinch to click/drag")
        } else {
            statusLabel.stringValue = camName.isEmpty ? "" : "• \(camName)"
        }
    }

    func windowWillClose(_ notification: Notification) {
        gesture.enabled = false
        tracker.stop()
        tracker.onResults = nil
    }

    @objc private func toggleFace(_ s: NSButton) { overlay?.showFace = (s.state == .on) }
    @objc private func toggleHands(_ s: NSButton) { overlay?.showHands = (s.state == .on) }
    @objc private func toggleBody(_ s: NSButton) { overlay?.showBody = (s.state == .on) }
    @objc private func toggleGesture(_ s: NSButton) { gesture.enabled = (s.state == .on); refreshStatus() }
    @objc private func cameraChanged(_ s: NSPopUpButton) {
        let i = s.indexOfSelectedItem
        if i >= 0, i < cameraList.count { tracker.use(cameraList[i]) }
    }
    @objc private func done() { window?.close() }

    private func build() {
        let W: CGFloat = 900, H: CGFloat = 560, barH: CGFloat = 48
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: H),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L.t(zh: "丝语 · 摄像头追踪", en: "Dontype · Camera Tracking")
        w.isReleasedWhenClosed = false
        w.delegate = self
        let content = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))

        // 预览区（底部留 barH 给状态/开关）
        let previewRect = NSRect(x: 0, y: barH, width: W, height: H - barH)
        let previewHost = NSView(frame: previewRect)
        previewHost.wantsLayer = true
        previewHost.layer?.backgroundColor = NSColor.black.cgColor
        let pl = AVCaptureVideoPreviewLayer(session: tracker.session)
        pl.videoGravity = .resizeAspect
        pl.frame = previewHost.bounds
        pl.transform = CATransform3DMakeScale(-1, 1, 1)   // 自拍镜像（绕中心水平翻）；叠加层在 toView 里也翻 X 对齐
        previewHost.layer?.addSublayer(pl)
        previewLayer = pl

        let ov = TrackingOverlayView(frame: previewHost.bounds)
        ov.previewLayer = pl
        overlay = ov
        previewHost.addSubview(ov)
        content.addSubview(previewHost)

        // 底栏：摄像头选择 + 手势开关 + 状态 + 三个显示开关 + 完成
        cameraList = CameraTracker.cameras()
        let pop = NSPopUpButton(frame: NSRect(x: 14, y: 11, width: 210, height: 26), pullsDown: false)
        for c in cameraList { pop.addItem(withTitle: c.localizedName) }
        let prefer = UserDefaults.standard.string(forKey: "cameraDeviceID")
        if let i = cameraList.firstIndex(where: { $0.uniqueID == prefer })
            ?? cameraList.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }) {
            pop.selectItem(at: i)
        }
        pop.target = self; pop.action = #selector(cameraChanged(_:))
        cameraPopup = pop
        content.addSubview(pop)

        // 手势控制鼠标（默认关，开了才接管）
        let g = NSButton(checkboxWithTitle: L.t(zh: "🖐 手势控制鼠标", en: "🖐 Gesture control"),
                         target: self, action: #selector(toggleGesture(_:)))
        g.state = .off; g.frame = NSRect(x: 234, y: 12, width: 150, height: 24)
        content.addSubview(g)

        statusLabel = NSTextField(labelWithString: "…")
        statusLabel.font = .systemFont(ofSize: 12); statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.frame = NSRect(x: 394, y: 14, width: 190, height: 20)
        content.addSubview(statusLabel)

        func chk(_ title: String, _ x: CGFloat, _ w: CGFloat, _ on: Bool, _ sel: Selector) -> NSButton {
            let b = NSButton(checkboxWithTitle: title, target: self, action: sel)
            b.state = on ? .on : .off; b.frame = NSRect(x: x, y: 12, width: w, height: 24); return b
        }
        content.addSubview(chk(L.t(zh: "脸", en: "Face"), W - 290, 46, false, #selector(toggleFace(_:))))
        content.addSubview(chk(L.t(zh: "手", en: "Hands"), W - 240, 46, true, #selector(toggleHands(_:))))
        content.addSubview(chk(L.t(zh: "身体", en: "Body"), W - 190, 64, false, #selector(toggleBody(_:))))
        let doneBtn = NSButton(title: L.t(zh: "完成", en: "Done"), target: self, action: #selector(done))
        doneBtn.bezelStyle = .rounded; doneBtn.keyEquivalent = "\r"
        doneBtn.frame = NSRect(x: W - 96, y: 9, width: 84, height: 28)
        content.addSubview(doneBtn)

        w.contentView = content
        window = w
    }
}

/// 关键点叠加层：把 Vision 的归一化坐标经预览层换算成视图坐标，画脸/手/身体的点。
final class TrackingOverlayView: NSView {
    override var isFlipped: Bool { true }   // 用左上原点，和 layerPointConverted 的输出对齐（否则上下相反）
    weak var previewLayer: AVCaptureVideoPreviewLayer?
    var showFace = false { didSet { needsDisplay = true } }   // 默认只看手
    var showHands = true { didSet { needsDisplay = true } }
    var showBody = false { didSet { needsDisplay = true } }
    private var results = CameraTracker.Results()

    func update(_ r: CameraTracker.Results) { results = r; needsDisplay = true }

    /// Vision 归一化点（左下原点）→ 预览层视图坐标；预览做了水平镜像，这里也翻 X 对齐。
    private func toView(_ v: CGPoint) -> CGPoint? {
        guard let pl = previewLayer else { return nil }
        let p = pl.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: v.x, y: 1 - v.y))
        return CGPoint(x: bounds.width - p.x, y: p.y)
    }

    private func dot(_ p: CGPoint, _ r: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)).fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        // 脸部关键点（相对人脸框归一化 → 图像归一化）
        if showFace {
            for face in results.faces {
                let b = face.boundingBox
                guard let pts = face.landmarks?.allPoints?.normalizedPoints else { continue }
                for p in pts {
                    let v = CGPoint(x: b.minX + p.x * b.width, y: b.minY + p.y * b.height)
                    if let pt = toView(v) { dot(pt, 1.6, .systemOrange) }
                }
            }
        }
        // 手（21 关节，图像归一化）
        if showHands {
            for hand in results.hands {
                guard let pts = try? hand.recognizedPoints(.all) else { continue }
                for (_, p) in pts where p.confidence > 0.3 {
                    if let pt = toView(p.location) { dot(pt, 3, .systemGreen) }
                }
            }
        }
        // 身体姿态
        if showBody {
            for body in results.bodies {
                guard let pts = try? body.recognizedPoints(.all) else { continue }
                for (_, p) in pts where p.confidence > 0.3 {
                    if let pt = toView(p.location) { dot(pt, 3.4, .systemBlue) }
                }
            }
        }
    }
}
