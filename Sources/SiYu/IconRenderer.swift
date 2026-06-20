import AppKit

/// 极简 SVG path-data → NSBezierPath。够用于本项目图标，支持 M m L l H h V v C c S s Z z。
enum SVGPath {
    static func parse(_ d: String) -> NSBezierPath {
        let s = Array(d)
        var idx = 0
        let path = NSBezierPath()
        var current = NSPoint.zero
        var startPt = NSPoint.zero
        var lastCtrl = NSPoint.zero
        var lastCmd: Character = " "

        func skipSep() {
            while idx < s.count {
                let c = s[idx]
                if c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" { idx += 1 } else { break }
            }
        }
        func readNumber() -> CGFloat {
            skipSep()
            var str = ""
            var hasDot = false
            if idx < s.count, s[idx] == "-" || s[idx] == "+" { str.append(s[idx]); idx += 1 }
            while idx < s.count {
                let c = s[idx]
                if c.isNumber { str.append(c); idx += 1 }
                else if c == "." { if hasDot { break }; hasDot = true; str.append(c); idx += 1 }
                else if c == "e" || c == "E" {
                    str.append(c); idx += 1
                    if idx < s.count, s[idx] == "-" || s[idx] == "+" { str.append(s[idx]); idx += 1 }
                } else { break }
            }
            return CGFloat(Double(str) ?? 0)
        }
        func wasCurve(_ c: Character) -> Bool { "CcSs".contains(c) }
        func reflected() -> NSPoint {
            wasCurve(lastCmd) ? NSPoint(x: 2 * current.x - lastCtrl.x, y: 2 * current.y - lastCtrl.y) : current
        }

        while true {
            skipSep()
            if idx >= s.count { break }
            var cmd = lastCmd
            if s[idx].isLetter {
                cmd = s[idx]
                idx += 1
            } else if lastCmd == "M" { cmd = "L" }
            else if lastCmd == "m" { cmd = "l" }

            switch cmd {
            case "M":
                current = NSPoint(x: readNumber(), y: readNumber()); startPt = current
                path.move(to: current)
            case "m":
                current = NSPoint(x: current.x + readNumber(), y: current.y + readNumber()); startPt = current
                path.move(to: current)
            case "L":
                current = NSPoint(x: readNumber(), y: readNumber()); path.line(to: current)
            case "l":
                current = NSPoint(x: current.x + readNumber(), y: current.y + readNumber()); path.line(to: current)
            case "H": current.x = readNumber(); path.line(to: current)
            case "h": current.x += readNumber(); path.line(to: current)
            case "V": current.y = readNumber(); path.line(to: current)
            case "v": current.y += readNumber(); path.line(to: current)
            case "C":
                let c1 = NSPoint(x: readNumber(), y: readNumber())
                let c2 = NSPoint(x: readNumber(), y: readNumber())
                let e = NSPoint(x: readNumber(), y: readNumber())
                path.curve(to: e, controlPoint1: c1, controlPoint2: c2)
                current = e; lastCtrl = c2
            case "c":
                let c1 = NSPoint(x: current.x + readNumber(), y: current.y + readNumber())
                let c2 = NSPoint(x: current.x + readNumber(), y: current.y + readNumber())
                let e = NSPoint(x: current.x + readNumber(), y: current.y + readNumber())
                path.curve(to: e, controlPoint1: c1, controlPoint2: c2)
                current = e; lastCtrl = c2
            case "S":
                let c1 = reflected()
                let c2 = NSPoint(x: readNumber(), y: readNumber())
                let e = NSPoint(x: readNumber(), y: readNumber())
                path.curve(to: e, controlPoint1: c1, controlPoint2: c2)
                current = e; lastCtrl = c2
            case "s":
                let c1 = reflected()
                let c2 = NSPoint(x: current.x + readNumber(), y: current.y + readNumber())
                let e = NSPoint(x: current.x + readNumber(), y: current.y + readNumber())
                path.curve(to: e, controlPoint1: c1, controlPoint2: c2)
                current = e; lastCtrl = c2
            case "A", "a":
                let rx = readNumber(), ry = readNumber(), rot = readNumber()
                let laf = readNumber(), sf = readNumber()
                var e = NSPoint(x: readNumber(), y: readNumber())
                if cmd == "a" { e.x += current.x; e.y += current.y }
                appendArc(path, from: current, to: e, rx: rx, ry: ry,
                          phiDeg: rot, largeArc: laf != 0, sweep: sf != 0)
                current = e
            case "Z", "z":
                path.close(); current = startPt
            default:
                idx += 1   // 跳过不认识的字符，避免死循环
            }
            lastCmd = cmd
        }
        return path
    }

    /// SVG 椭圆弧（端点参数化）→ 贝塞尔曲线逼近（每段 ≤90°），SVG 规范 F.6.5
    private static func appendArc(_ path: NSBezierPath, from p0: NSPoint, to p1: NSPoint,
                                  rx rxIn: CGFloat, ry ryIn: CGFloat, phiDeg: CGFloat,
                                  largeArc: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx < 1e-6 || ry < 1e-6 || (p0.x == p1.x && p0.y == p1.y) {
            path.line(to: p1); return
        }
        let phi = phiDeg * .pi / 180
        let cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosP * dx + sinP * dy
        let y1p = -sinP * dx + cosP * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { let s = sqrt(lambda); rx *= s; ry *= s }
        let num = rx*rx*ry*ry - rx*rx*y1p*y1p - ry*ry*x1p*x1p
        let den = rx*rx*y1p*y1p + ry*ry*x1p*x1p
        var coef = den > 0 ? sqrt(max(0, num / den)) : 0
        if largeArc == sweep { coef = -coef }
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx
        let cx = cosP * cxp - sinP * cyp + (p0.x + p1.x) / 2
        let cy = sinP * cxp + cosP * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux*ux + uy*uy) * (vx*vx + vy*vy))
            guard len > 0 else { return 0 }
            var ang = acos(min(1, max(-1, dot / len)))
            if ux * vy - uy * vx < 0 { ang = -ang }
            return ang
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var dtheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && dtheta > 0 { dtheta -= 2 * .pi }
        if sweep && dtheta < 0 { dtheta += 2 * .pi }

        let segs = max(1, Int(ceil(abs(dtheta) / (.pi / 2))))
        let delta = dtheta / CGFloat(segs)
        let t = 4.0 / 3.0 * tan(delta / 4)
        var th = theta1
        var prev = p0
        for _ in 0..<segs {
            let th2 = th + delta
            let cos1 = cos(th), sin1 = sin(th), cos2 = cos(th2), sin2 = sin(th2)
            let ex = cx + rx * cos2 * cosP - ry * sin2 * sinP
            let ey = cy + rx * cos2 * sinP + ry * sin2 * cosP
            let d1x = -rx * sin1 * cosP - ry * cos1 * sinP
            let d1y = -rx * sin1 * sinP + ry * cos1 * cosP
            let d2x = -rx * sin2 * cosP - ry * cos2 * sinP
            let d2y = -rx * sin2 * sinP + ry * cos2 * cosP
            let e = NSPoint(x: ex, y: ey)
            path.curve(to: e,
                       controlPoint1: NSPoint(x: prev.x + t * d1x, y: prev.y + t * d1y),
                       controlPoint2: NSPoint(x: ex - t * d2x, y: ey - t * d2y))
            prev = e
            th = th2
        }
    }
}

/// 麦克风来源（药丸里显示对应图标）
enum MicSourceKind {
    case off       // 无可用输入设备（红）
    case builtin   // 电脑内置麦克风
    case phone     // iPhone/iPad 连续互通
    case external  // 外置：USB 摄像头 / 有线 / 蓝牙等
}

/// 药丸里的麦克风来源图标（tabler icons，SVG 路径实时绘制）
enum MicIcon {
    private static let off = [
        SVGPath.parse("M3 3l18 18"),
        SVGPath.parse("M9 5a3 3 0 0 1 6 0v5a3 3 0 0 1 -.13 .874m-2 2a3 3 0 0 1 -3.87 -2.872v-1"),
        SVGPath.parse("M5 10a7 7 0 0 0 10.846 5.85m2 -2a6.967 6.967 0 0 0 1.152 -3.85"),
        SVGPath.parse("M8 21l8 0"),
        SVGPath.parse("M12 17l0 4"),
    ]
    private static let external_ = [
        SVGPath.parse("M15 12.9a5 5 0 1 0 -3.902 -3.9"),
        SVGPath.parse("M15 12.9l-3.902 -3.899l-7.513 8.584a2 2 0 1 0 2.827 2.83l8.588 -7.515"),
    ]
    private static let laptop = [
        SVGPath.parse("M3 19l18 0"),
        SVGPath.parse("M5 7a1 1 0 0 1 1 -1h12a1 1 0 0 1 1 1v8a1 1 0 0 1 -1 1h-12a1 1 0 0 1 -1 -1l0 -8"),
    ]
    private static let mobile = [
        SVGPath.parse("M6 5a2 2 0 0 1 2 -2h8a2 2 0 0 1 2 2v14a2 2 0 0 1 -2 2h-8a2 2 0 0 1 -2 -2v-14"),
        SVGPath.parse("M11 4h2"),
        SVGPath.parse("M12 17v.01"),
    ]

    static func image(for kind: MicSourceKind, size: CGFloat = 18) -> NSImage {
        let paths: [NSBezierPath]
        let color: NSColor
        switch kind {
        case .off:      paths = off;       color = .systemRed
        case .external: paths = external_; color = .white
        case .builtin:  paths = laptop;    color = .white
        case .phone:    paths = mobile;    color = .white
        }
        let scale = size / 24.0
        return NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let t = NSAffineTransform()
            t.scale(by: scale)
            t.concat()
            color.setStroke()
            for p in paths {
                p.lineWidth = 2
                p.lineCapStyle = .round
                p.lineJoinStyle = .round
                p.stroke()
            }
            return true
        }
    }
}

/// 菜单栏图标的三种状态，全部由 SVG 矢量路径实时绘制。
/// 用品牌 logo 线稿版（siyu-menu-logo.svg，viewBox 19×17.9）：上半穹顶 + 下半球+赤道+尾巴。单色模板，跟随系统黑/白。
enum MenuIcon {
    enum State { case idle, recording, processing }

    // 下半球 + 赤道 + 尾巴（闭合）
    private static let lowerTail = SVGPath.parse("M15.3,14.3s.1,0,.2-.1c1.8-1.5,3-3.5,3-5.9-1,.7-4.2,3-9,3-4.79-.1-8.08-2.48-8.99-3.29,0,.06-.01,.13-.01,.19v.1c0,4.3,4,7.7,9,7.7,.4,0,1.1,0,2.1-.1,1.3,.8,3.1,1.5,4.7,1.5,.5,0,.7-.4,.4-.8-.5-.6-1.1-1.6-1.4-2.3Z")
    // 上半穹顶（闭合）
    private static let upperDome = SVGPath.parse("M18.5,8.3C18.5,4,14.4,.5,9.5,.5h-.1C4.57,.5,.63,3.8,.51,8.01c.91,.81,4.2,3.19,8.99,3.29,4.8,0,8-2.3,9-3Z")
    private static let parts = [lowerTail, upperDome]

    static func image(for state: State, size: CGFloat = 18) -> NSImage {
        let glyphScale = (size * 0.92) / 19.0     // 19×17.9 的图形等比缩放、留点边
        let gw = 19.0 * glyphScale, gh = 17.9 * glyphScale
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let t = NSAffineTransform()
            t.translateX(by: (size - gw) / 2, yBy: (size - gh) / 2)   // 居中
            t.scaleX(by: glyphScale, yBy: glyphScale)
            t.concat()

            switch state {
            case .idle:
                // 上半穹顶空心描边 + 下半球+尾巴实心（template：系统自动着色）
                NSColor.black.setFill()
                lowerTail.fill()
                NSColor.black.setStroke()
                upperDome.lineWidth = 1.6
                upperDome.lineCapStyle = .round
                upperDome.lineJoinStyle = .round
                upperDome.stroke()
            case .recording:
                NSColor.systemRed.setFill()  // 实心红：正在录音
                for p in parts { p.fill() }
            case .processing:
                NSColor.systemOrange.setFill() // 实心橙：整理中
                for p in parts { p.fill() }
            }
            return true
        }
        img.isTemplate = (state == .idle)
        return img
    }
}

/// 语音助手菜单项图标：Tabler「message-chatbot」描边版（template，跟随菜单浅/深色着色）。
enum AssistantIcon {
    private static let paths: [NSBezierPath] = [
        SVGPath.parse("M18 4a3 3 0 0 1 3 3v8a3 3 0 0 1 -3 3h-5l-5 3v-3h-2a3 3 0 0 1 -3 -3v-8a3 3 0 0 1 3 -3h12"),
        SVGPath.parse("M9.5 9h.01"),
        SVGPath.parse("M14.5 9h.01"),
        SVGPath.parse("M9.5 13a3.5 3.5 0 0 0 5 0"),
    ]
    static func image(size: CGFloat = 16) -> NSImage {
        let scale = size / 24.0   // viewBox 24×24
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let t = NSAffineTransform(); t.scaleX(by: scale, yBy: scale); t.concat()
            NSColor.black.setStroke()
            for p in paths {
                p.lineWidth = 2; p.lineCapStyle = .round; p.lineJoinStyle = .round
                p.stroke()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
