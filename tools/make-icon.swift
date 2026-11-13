// Рисует иконку приложения (1024×1024): снежинка на зимнем фоне.
// Запуск: ./tools/make-icon.sh  (создаёт Resources/AppIcon.icns)

import Cocoa

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Плашка по сетке иконок macOS: 824×824, скругление ~185.
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)

// лёгкая тень под плашкой
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(platePath)
ctx.setFillColor(CGColor(red: 0.05, green: 0.12, blue: 0.3, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(platePath)
ctx.clip()
// ночное небо
let sky = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.04, green: 0.1, blue: 0.3, alpha: 1),
    CGColor(red: 0.12, green: 0.32, blue: 0.62, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// сугроб внизу
let drift = CGMutablePath()
drift.move(to: CGPoint(x: 100, y: 100))
drift.addLine(to: CGPoint(x: 100, y: 250))
drift.addCurve(to: CGPoint(x: 520, y: 215), control1: CGPoint(x: 230, y: 300), control2: CGPoint(x: 380, y: 190))
drift.addCurve(to: CGPoint(x: 924, y: 275), control1: CGPoint(x: 660, y: 240), control2: CGPoint(x: 800, y: 320))
drift.addLine(to: CGPoint(x: 924, y: 100))
drift.closeSubpath()
ctx.addPath(drift)
ctx.setFillColor(CGColor(red: 0.93, green: 0.96, blue: 1, alpha: 1))
ctx.fillPath()
// падающие снежинки-точки
var seed: UInt64 = 7
func rand() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
for _ in 0..<55 {
    let x = 110 + rand() * 804, y = 260 + rand() * 650, r = 3 + rand() * 7
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.35 + rand() * 0.5))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}
ctx.restoreGState()

// Снежинка: 6 лучей с веточками, мягкое свечение.
let flake = CGMutablePath()
let c = CGPoint(x: 512, y: 560), R: CGFloat = 270
for k in 0..<6 {
    let a = CGFloat(k) * .pi / 3 + .pi / 2
    func p(_ d: CGFloat, _ da: CGFloat = 0) -> CGPoint { CGPoint(x: c.x + cos(a + da) * d, y: c.y + sin(a + da) * d) }
    flake.move(to: c)
    flake.addLine(to: p(R))
    for (at, len) in [(0.42, 0.3), (0.7, 0.22)] as [(CGFloat, CGFloat)] {
        let base = p(R * at)
        for side in [-1, 1] as [CGFloat] {
            let b = a + side * .pi / 4
            flake.move(to: base)
            flake.addLine(to: CGPoint(x: base.x + cos(b) * R * len, y: base.y + sin(b) * R * len))
        }
    }
}
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 40, color: CGColor(red: 0.6, green: 0.85, blue: 1, alpha: 0.9))
ctx.addPath(flake)
ctx.setStrokeColor(.white)
ctx.setLineWidth(40)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.strokePath()
ctx.restoreGState()
ctx.setFillColor(.white)
ctx.fillEllipse(in: CGRect(x: c.x - 42, y: c.y - 42, width: 84, height: 84))

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
