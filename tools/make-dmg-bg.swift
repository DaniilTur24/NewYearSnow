// Фон окна установщика (.dmg): «перетащите снежинку в Программы» + подсказка про «Всё равно открыть».
// Запуск: swift tools/make-dmg-bg.swift <out.png> <масштаб 1|2>
// Размер окна 640×420; значки стоят в (160,190) и (480,190) — считая от левого верхнего угла.

import Cocoa

let out = CommandLine.arguments[1]
let k = CGFloat(Double(CommandLine.arguments[2]) ?? 1)
let W: CGFloat = 640, H: CGFloat = 420
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(W * k), height: Int(H * k), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: k, y: k)

// светлое зимнее небо
let sky = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.84, green: 0.91, blue: 1, alpha: 1),
    CGColor(red: 0.97, green: 0.98, blue: 1, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

// падающий снег
var seed: UInt64 = 42
func rand() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
for _ in 0..<70 {
    let x = rand() * W, y = 90 + rand() * (H - 90), r = 1.5 + rand() * 2.5
    ctx.setFillColor(CGColor(red: 0.55, green: 0.7, blue: 0.92, alpha: 0.25 + rand() * 0.3))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

// сугроб внизу
let drift = CGMutablePath()
drift.move(to: CGPoint(x: 0, y: 0))
drift.addLine(to: CGPoint(x: 0, y: 70))
drift.addCurve(to: CGPoint(x: 330, y: 58), control1: CGPoint(x: 110, y: 96), control2: CGPoint(x: 230, y: 44))
drift.addCurve(to: CGPoint(x: W, y: 82), control1: CGPoint(x: 450, y: 74), control2: CGPoint(x: 560, y: 100))
drift.addLine(to: CGPoint(x: W, y: 0))
drift.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 8, color: CGColor(red: 0.4, green: 0.55, blue: 0.8, alpha: 0.35))
ctx.addPath(drift)
ctx.setFillColor(.white)
ctx.fillPath()
ctx.restoreGState()

// текст
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
let dark = NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.4, alpha: 1)
func text(_ s: String, _ font: NSFont, _ color: NSColor, centerY: CGFloat) {
    let p = NSMutableParagraphStyle()
    p.alignment = .center
    let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
    let h = a.boundingRect(with: NSSize(width: W - 60, height: 200), options: .usesLineFragmentOrigin).height
    a.draw(with: NSRect(x: 30, y: centerY - h / 2, width: W - 60, height: h), options: .usesLineFragmentOrigin)
}
text("Перетащите снежинку в «Программы»", .systemFont(ofSize: 21, weight: .bold), dark, centerY: H - 52)

// стрелка между значками (значки по центру на y = 190 от верха)
let ay = H - 190
let arrow = CGMutablePath()
arrow.move(to: CGPoint(x: 240, y: ay + 6))
arrow.addQuadCurve(to: CGPoint(x: 395, y: ay + 6), control: CGPoint(x: 318, y: ay + 44))
ctx.setStrokeColor(CGColor(red: 0.2, green: 0.45, blue: 0.85, alpha: 0.9))
ctx.setLineWidth(5)
ctx.setLineCap(.round)
ctx.setLineDash(phase: 0, lengths: [1, 11])
ctx.addPath(arrow)
ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [])
let tip = CGPoint(x: 402, y: ay + 2)
let head = CGMutablePath()
head.move(to: CGPoint(x: tip.x - 16, y: tip.y + 14))
head.addLine(to: tip)
head.addLine(to: CGPoint(x: tip.x - 20, y: tip.y - 6))
ctx.setLineJoin(.round)
ctx.addPath(head)
ctx.strokePath()

// подсказка внизу
text("Затем откройте NewYearSnow в «Программах».\nЕсли macOS не пустит: Системные настройки → Конфиденциальность\nи безопасность → «Всё равно открыть».",
     .systemFont(ofSize: 12.5, weight: .medium), dark.withAlphaComponent(0.85), centerY: 92)

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
rep.size = NSSize(width: W, height: H)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
