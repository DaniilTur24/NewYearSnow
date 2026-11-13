// Картинка-превью для ссылки (Telegram, соцсети): 1200×630.
// Запуск: swift tools/make-og.swift Resources/icon.png docs/og.png
import Cocoa
let icon = NSImage(contentsOfFile: CommandLine.arguments[1])!
let W: CGFloat = 1200, H: CGFloat = 630
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let sky = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.03, green: 0.08, blue: 0.24, alpha: 1),
                                               CGColor(red: 0.1, green: 0.28, blue: 0.56, alpha: 1)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
var seed: UInt64 = 3
func rand() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
for _ in 0..<160 {
    let x = rand() * W, y = rand() * H, r = 1.5 + rand() * 3.5
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.25 + rand() * 0.55))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}
// гирлянда сверху
let colors: [CGColor] = [CGColor(red: 1, green: 0.25, blue: 0.3, alpha: 1), CGColor(red: 1, green: 0.8, blue: 0.2, alpha: 1),
                         CGColor(red: 0.25, green: 0.9, blue: 0.45, alpha: 1), CGColor(red: 0.3, green: 0.6, blue: 1, alpha: 1),
                         CGColor(red: 1, green: 0.45, blue: 0.9, alpha: 1)]
for i in 0..<24 {
    let x = 25 + CGFloat(i) * 50, y = H - 26 - 10 * sin(CGFloat(i % 4) / 3 * .pi)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 18, color: colors[i % 5])
    ctx.setFillColor(colors[i % 5])
    ctx.fillEllipse(in: CGRect(x: x - 7, y: y - 20, width: 14, height: 22))
    ctx.restoreGState()
}
// сугроб
let drift = CGMutablePath()
drift.move(to: CGPoint(x: 0, y: 0)); drift.addLine(to: CGPoint(x: 0, y: 95))
drift.addCurve(to: CGPoint(x: 600, y: 80), control1: CGPoint(x: 200, y: 130), control2: CGPoint(x: 420, y: 60))
drift.addCurve(to: CGPoint(x: W, y: 110), control1: CGPoint(x: 800, y: 100), control2: CGPoint(x: 1000, y: 140))
drift.addLine(to: CGPoint(x: W, y: 0)); drift.closeSubpath()
ctx.addPath(drift); ctx.setFillColor(CGColor(red: 0.94, green: 0.97, blue: 1, alpha: 1)); ctx.fillPath()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
icon.draw(in: NSRect(x: 90, y: 175, width: 300, height: 300))
let title = NSAttributedString(string: "Новогодний снег\nдля Mac", attributes: [
    .font: NSFont.systemFont(ofSize: 76, weight: .heavy), .foregroundColor: NSColor.white])
title.draw(at: NSPoint(x: 430, y: 290))
let sub = NSAttributedString(string: "Снег, сугробы на окнах и Доке, гирлянды,\nсалют, Санта и рождественская музыка", attributes: [
    .font: NSFont.systemFont(ofSize: 30, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.82)])
sub.draw(at: NSPoint(x: 434, y: 180))
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
