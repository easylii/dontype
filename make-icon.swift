import AppKit

// 复用项目里的极简 SVG path 解析（仅本图标需要的命令子集）
func parse(_ d: String) -> NSBezierPath {
    let s = Array(d); var idx = 0
    let path = NSBezierPath()
    var current = NSPoint.zero, startPt = NSPoint.zero, lastCtrl = NSPoint.zero
    var lastCmd: Character = " "
    func skipSep() { while idx < s.count { let c = s[idx]; if c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" { idx += 1 } else { break } } }
    func readNumber() -> CGFloat {
        skipSep(); var str = ""; var hasDot = false
        if idx < s.count, s[idx] == "-" || s[idx] == "+" { str.append(s[idx]); idx += 1 }
        while idx < s.count { let c = s[idx]
            if c.isNumber { str.append(c); idx += 1 }
            else if c == "." { if hasDot { break }; hasDot = true; str.append(c); idx += 1 }
            else if c == "e" || c == "E" { str.append(c); idx += 1; if idx < s.count, s[idx] == "-" || s[idx] == "+" { str.append(s[idx]); idx += 1 } }
            else { break } }
        return CGFloat(Double(str) ?? 0)
    }
    func wasCurve(_ c: Character) -> Bool { "CcSs".contains(c) }
    func reflected() -> NSPoint { wasCurve(lastCmd) ? NSPoint(x: 2*current.x-lastCtrl.x, y: 2*current.y-lastCtrl.y) : current }
    while true {
        skipSep(); if idx >= s.count { break }
        var cmd = lastCmd
        if s[idx].isLetter { cmd = s[idx]; idx += 1 }
        else if lastCmd == "M" { cmd = "L" } else if lastCmd == "m" { cmd = "l" }
        switch cmd {
        case "M": current = NSPoint(x: readNumber(), y: readNumber()); startPt = current; path.move(to: current)
        case "m": current = NSPoint(x: current.x+readNumber(), y: current.y+readNumber()); startPt = current; path.move(to: current)
        case "L": current = NSPoint(x: readNumber(), y: readNumber()); path.line(to: current)
        case "l": current = NSPoint(x: current.x+readNumber(), y: current.y+readNumber()); path.line(to: current)
        case "H": current.x = readNumber(); path.line(to: current)
        case "h": current.x += readNumber(); path.line(to: current)
        case "V": current.y = readNumber(); path.line(to: current)
        case "v": current.y += readNumber(); path.line(to: current)
        case "C":
            let c1 = NSPoint(x: readNumber(), y: readNumber()), c2 = NSPoint(x: readNumber(), y: readNumber()), e = NSPoint(x: readNumber(), y: readNumber())
            path.curve(to: e, controlPoint1: c1, controlPoint2: c2); current = e; lastCtrl = c2
        case "c":
            let c1 = NSPoint(x: current.x+readNumber(), y: current.y+readNumber()), c2 = NSPoint(x: current.x+readNumber(), y: current.y+readNumber()), e = NSPoint(x: current.x+readNumber(), y: current.y+readNumber())
            path.curve(to: e, controlPoint1: c1, controlPoint2: c2); current = e; lastCtrl = c2
        case "S":
            let c1 = reflected(), c2 = NSPoint(x: readNumber(), y: readNumber()), e = NSPoint(x: readNumber(), y: readNumber())
            path.curve(to: e, controlPoint1: c1, controlPoint2: c2); current = e; lastCtrl = c2
        case "s":
            let c1 = reflected(), c2 = NSPoint(x: current.x+readNumber(), y: current.y+readNumber()), e = NSPoint(x: current.x+readNumber(), y: current.y+readNumber())
            path.curve(to: e, controlPoint1: c1, controlPoint2: c2); current = e; lastCtrl = c2
        case "Z", "z": path.close(); current = startPt
        default: idx += 1
        }
        lastCmd = cmd
    }
    return path
}

// logo（siyu-app-logo.svg，viewBox 18×17.9）：上下两块 —— 上半淡黄、下半深橙+尾巴。
let lowerApp = parse("M14.8,14.8s.1,0,.2-.1c1.8-1.5,3-3.5,3-5.9-1,.7-4.2,3-9,3C4.21,11.7,.92,9.32,.01,8.51c0,.06-.01,.13-.01,.19v.1c0,4.3,4,7.7,9,7.7,.4,0,1.1,0,2.1-.1,1.3,.8,3.1,1.5,4.7,1.5,.5,0,.7-.4,.4-.8-.5-.6-1.1-1.6-1.4-2.3Z")
let upperApp = parse("M18,7.8C18,3.5,13.9,0,9,0h-.1C4.07,0,.13,3.3,.01,7.51c.91,.81,4.2,3.19,8.99,3.29,4.8,0,8-2.3,9-3Z")

func hex(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
}
let cLower = hex(0xEB, 0x5F, 0x27)   // 深橙 · 下半+尾巴
let cUpper = hex(0xFF, 0xC9, 0x7E)   // 淡黄 · 上半

let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()

// 白色圆角方块背景（留边，符合 macOS 图标网格；四角透明）
let margin: CGFloat = 90
let rect = NSRect(x: margin, y: margin, width: S-2*margin, height: S-2*margin)
let radius = (S-2*margin) * 0.2237
let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
NSColor.white.setFill()
squircle.fill()
// 极细暖灰描边，让白底图标在浅色背景（Dock/Finder）上也有边界
hex(0xEA, 0xE2, 0xD8).setStroke()
squircle.lineWidth = 3
squircle.stroke()

// 把 18×17.9 坐标系映射到方块内居中、约 60% 大小
let glyphW: CGFloat = (S-2*margin) * 0.60
let scale = glyphW / 18.0
let glyphH = 17.9 * scale
let tx = rect.midX - glyphW/2
let ty = rect.midY - glyphH/2
let xform = NSAffineTransform()
xform.translateX(by: tx, yBy: ty + glyphH)   // flip：SVG 顶左原点 → AppKit 底左
xform.scaleX(by: scale, yBy: -scale)
xform.concat()

cLower.setFill(); lowerApp.fill()
cUpper.setFill(); upperApp.fill()

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("PNG 生成失败\n".data(using: .utf8)!); exit(1)
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("✓ \(out)")
