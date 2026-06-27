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

/// 摄像头窗口：实时预览 + 脸/手/身体关键点叠加 + 三个显示开关。
final class CameraWindow: NSObject, NSWindowDelegate {
    private let tracker = CameraTracker()
    private var window: NSWindow?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var overlay: TrackingOverlayView?
    private var statusLabel: NSTextField!

    func show() {
        if window == nil { build() }
        tracker.onStatus = { [weak self] s in self?.statusLabel.stringValue = "• \(s)" }
        tracker.onResults = { [weak self] r in self?.overlay?.update(r) }
        tracker.start()
        NSApp.activate(ignoringOtherApps: true)
        window?.center(); window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        tracker.stop()
        tracker.onResults = nil
    }

    @objc private func toggleFace(_ s: NSButton) { overlay?.showFace = (s.state == .on) }
    @objc private func toggleHands(_ s: NSButton) { overlay?.showHands = (s.state == .on) }
    @objc private func toggleBody(_ s: NSButton) { overlay?.showBody = (s.state == .on) }
    @objc private func done() { window?.close() }

    private func build() {
        let W: CGFloat = 760, H: CGFloat = 560, barH: CGFloat = 48
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
        previewHost.layer?.addSublayer(pl)
        previewLayer = pl

        let ov = TrackingOverlayView(frame: previewHost.bounds)
        ov.previewLayer = pl
        overlay = ov
        previewHost.addSubview(ov)
        content.addSubview(previewHost)

        // 底栏：状态 + 三个开关 + 完成
        statusLabel = NSTextField(labelWithString: "…")
        statusLabel.font = .systemFont(ofSize: 12); statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 14, y: 14, width: 240, height: 20)
        content.addSubview(statusLabel)

        func chk(_ title: String, _ x: CGFloat, _ sel: Selector) -> NSButton {
            let b = NSButton(checkboxWithTitle: title, target: self, action: sel)
            b.state = .on; b.frame = NSRect(x: x, y: 12, width: 78, height: 24); return b
        }
        content.addSubview(chk(L.t(zh: "脸", en: "Face"), W - 320, #selector(toggleFace(_:))))
        content.addSubview(chk(L.t(zh: "手", en: "Hands"), W - 250, #selector(toggleHands(_:))))
        content.addSubview(chk(L.t(zh: "身体", en: "Body"), W - 178, #selector(toggleBody(_:))))
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
