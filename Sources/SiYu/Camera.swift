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
        guard let cam = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: cam) else {
            onStatus?("找不到摄像头"); return
        }
        session.beginConfiguration()
        session.sessionPreset = .high
        if session.canAddInput(input) { session.addInput(input) }
        output.setSampleBufferDelegate(self, queue: queue)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        if session.canAddOutput(output) { session.addOutput(output) }
        if let conn = output.connection(with: .video) { conn.isVideoMirrored = false }  // 不镜像，叠加层才对齐
        session.commitConfiguration()
        running = true
        onStatus?("摄像头：\(cam.localizedName)")
        FileLog.write("📷 摄像头追踪启动：\(cam.localizedName)")
        queue.async { self.session.startRunning() }
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
    var minCutoff = 0.8, beta = 0.4, dCutoff = 1.0
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
    var gain: CGFloat = (NSScreen.main?.frame.width ?? 1440) * 2.2   // 归一化位移 → 屏幕像素

    private var filterX = OneEuroFilter()        // One-Euro 平滑食指位置，治抖
    private var filterY = OneEuroFilter()
    private var lastIndex: CGPoint?
    private var smoothRatio: Double = -1          // 捏合比例的低通
    private var pinching = false
    private var pinchStreak = 0                   // 连续几帧想翻转 → 去抖
    private var cursor: CGPoint = .zero           // 屏幕坐标（左上原点）

    private func begin() {
        let m = NSEvent.mouseLocation
        let h = NSScreen.main?.frame.height ?? 900
        cursor = CGPoint(x: m.x, y: h - m.y)
        filterX.reset(); filterY.reset(); lastIndex = nil; smoothRatio = -1; pinching = false; pinchStreak = 0
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
            filterX.reset(); filterY.reset(); lastIndex = nil   // 手丢了：复位，避免重新出现时跳
            return
        }
        let t = ProcessInfo.processInfo.systemUptime
        let s = CGPoint(x: CGFloat(filterX.filter(Double(idx.location.x), t)),
                        y: CGFloat(filterY.filter(Double(idx.location.y), t)))
        defer { lastIndex = s }

        // 捏合：拇指-食指距离 / 手掌尺度（缩放无关）→ 低通 → 滞回 + 连续 2 帧去抖
        let span = Double(max(0.0001, hypot(wrist.location.x - mcp.location.x, wrist.location.y - mcp.location.y)))
        let rawRatio = Double(hypot(thumb.location.x - idx.location.x, thumb.location.y - idx.location.y)) / span
        smoothRatio = smoothRatio < 0 ? rawRatio : (smoothRatio * 0.6 + rawRatio * 0.4)
        let want = pinching ? (smoothRatio < 0.75) : (smoothRatio < 0.5)
        if want != pinching {
            pinchStreak += 1
            if pinchStreak >= 2 {
                pinching = want; pinchStreak = 0
                post(pinching ? .leftMouseDown : .leftMouseUp); onPinch?(pinching)
            }
        } else { pinchStreak = 0 }

        guard let last = lastIndex else { return }
        var dx = s.x - last.x, dy = s.y - last.y
        if abs(dx) < 0.0015 { dx = 0 }
        if abs(dy) < 0.0015 { dy = 0 }
        let g = gain * (pinching ? 0.35 : 1.0)       // 捏合时降速，点击更稳、少误拖
        if let scr = NSScreen.main?.frame {
            cursor.x = min(max(0, cursor.x - dx * g), scr.width - 1)
            cursor.y = min(max(0, cursor.y - dy * g), scr.height - 1)
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
            statusLabel.stringValue = "• \(camName)"
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
    @objc private func done() { window?.close() }

    private func build() {
        let W: CGFloat = 840, H: CGFloat = 560, barH: CGFloat = 48
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
        if let conn = pl.connection, conn.isVideoMirroringSupported {   // 自拍镜像（layerPointConverted 会跟着镜像，叠加层仍对齐）
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = true
        }
        previewHost.layer?.addSublayer(pl)
        previewLayer = pl

        let ov = TrackingOverlayView(frame: previewHost.bounds)
        ov.previewLayer = pl
        overlay = ov
        previewHost.addSubview(ov)
        content.addSubview(previewHost)

        // 底栏：状态 + 手势控制开关 + 三个显示开关 + 完成
        statusLabel = NSTextField(labelWithString: "…")
        statusLabel.font = .systemFont(ofSize: 12); statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 14, y: 14, width: 318, height: 20)
        content.addSubview(statusLabel)

        func chk(_ title: String, _ x: CGFloat, _ w: CGFloat, _ sel: Selector) -> NSButton {
            let b = NSButton(checkboxWithTitle: title, target: self, action: sel)
            b.state = .on; b.frame = NSRect(x: x, y: 12, width: w, height: 24); return b
        }
        // 手势控制鼠标（默认关，开了才接管）
        let g = NSButton(checkboxWithTitle: L.t(zh: "🖐 手势控制鼠标", en: "🖐 Gesture control"),
                         target: self, action: #selector(toggleGesture(_:)))
        g.state = .off; g.frame = NSRect(x: 340, y: 12, width: 150, height: 24)
        content.addSubview(g)
        content.addSubview(chk(L.t(zh: "脸", en: "Face"), W - 290, 46, #selector(toggleFace(_:))))
        content.addSubview(chk(L.t(zh: "手", en: "Hands"), W - 240, 46, #selector(toggleHands(_:))))
        content.addSubview(chk(L.t(zh: "身体", en: "Body"), W - 190, 64, #selector(toggleBody(_:))))
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
    var showFace = true { didSet { needsDisplay = true } }
    var showHands = true { didSet { needsDisplay = true } }
    var showBody = true { didSet { needsDisplay = true } }
    private var results = CameraTracker.Results()

    func update(_ r: CameraTracker.Results) { results = r; needsDisplay = true }

    /// Vision 归一化点（左下原点）→ 预览层视图坐标。
    private func toView(_ v: CGPoint) -> CGPoint? {
        guard let pl = previewLayer else { return nil }
        return pl.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: v.x, y: 1 - v.y))
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
