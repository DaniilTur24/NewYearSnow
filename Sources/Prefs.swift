// Общие настройки, константы и маленькие помощники.

import Cocoa
import QuartzCore

// MARK: - Константы

let colW: CGFloat = 3            // ширина одной «колонки» сугроба, px
let gravity: CGFloat = -1600     // гравитация для комков снега, px/s²
let knockRadius: CGFloat = 12    // радиус «лопаты» курсора, px
let shakeSpeed: CGFloat = 2000   // скорость окна (px/s), при которой снег слетает
let maxChunks = 4000             // максимум летящих комков одновременно
let forgetAfter: Double = 900    // сколько секунд помнить сугроб невидимого окна (другой Space)
let dockPileID = -1

func bottomPileID(_ screenIndex: Int) -> Int { -100 - screenIndex }
func tabPileID(window: Int, index: Int) -> Int { -(1_000_000 + window * 100 + index) }

func rnd(_ a: CGFloat, _ b: CGFloat) -> CGFloat { CGFloat.random(in: a...b) }
func rndD(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b) }
func clamp(_ v: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { min(max(v, a), b) }

// MARK: - Настройки (хранятся в UserDefaults)

@propertyWrapper
struct Pref<T> {
    let key: String
    let def: T
    init(_ key: String, _ def: T) { self.key = key; self.def = def }
    var wrappedValue: T {
        get { UserDefaults.standard.object(forKey: key) as? T ?? def }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

enum S {
    // снег
    @Pref("snowing", true) static var snowing: Bool
    @Pref("mode", 1) static var mode: Int                          // 0 — лёгкий, 1 — средний, 2 — максимальный
    @Pref("piles", true) static var piles: Bool
    @Pref("windowAlpha", 0.1) static var windowAlpha: Double       // прозрачность снега над окнами
    // украшения
    @Pref("icicles", true) static var icicles: Bool
    @Pref("cursorWind", true) static var cursorWind: Bool
    @Pref("bottomSnow", true) static var bottomSnow: Bool
    @Pref("tabSnow", true) static var tabSnow: Bool
    @Pref("garland", true) static var garland: Bool
    @Pref("garlandMode", 0) static var garlandMode: Int
    @Pref("garlandSize", 1.7) static var garlandSize: Double    // размер лампочек гирлянды
    @Pref("fireworks", true) static var fireworks: Bool
    @Pref("countdown", true) static var countdown: Bool
    @Pref("santa", true) static var santa: Bool
    @Pref("sounds", true) static var sounds: Bool
    @Pref("music", false) static var music: Bool                  // рождественская музыка
    // прочее
    @Pref("autoOff", true) static var autoOff: Bool
    @Pref("giftsCaught", 0) static var giftsCaught: Int
}

// MARK: - Режимы зимы

struct WinterMode {
    let title: String
    let snowfall: Float        // густота снегопада над пустым столом
    let overWindows: Float     // снежинки поверх окон (0 — снег идёт только на фоне рабочего стола)
    let fallSpeed: Float       // скорость падения снежинок
    let flakeSize: Float       // размер снежинок
    let pileScale: CGFloat     // высота сугробов
    let growSeconds: CGFloat   // за сколько секунд нарастает сугроб
    let icicleCount: CGFloat   // сколько сосулек (множитель)
    let icicleLength: CGFloat  // длина сосулек (множитель)
    let wind: CGFloat          // постоянный ветер
    let gusts: CGFloat         // сила порывов ветра

    static let all = [
        WinterMode(title: "Лёгкий", snowfall: 0.25, overWindows: 0, fallSpeed: 0.85, flakeSize: 0.9,
                   pileScale: 0.55, growSeconds: 70, icicleCount: 0.35, icicleLength: 0.6, wind: 0, gusts: 0),
        WinterMode(title: "Средний", snowfall: 1, overWindows: 0, fallSpeed: 1, flakeSize: 1,
                   pileScale: 1, growSeconds: 40, icicleCount: 1, icicleLength: 1, wind: 0, gusts: 0),
        WinterMode(title: "Максимальный", snowfall: 3.2, overWindows: 0, fallSpeed: 1.6, flakeSize: 1.15,
                   pileScale: 1.6, growSeconds: 18, icicleCount: 2, icicleLength: 1.6, wind: 25, gusts: 35),
    ]
    static var current: WinterMode { all[max(0, min(all.count - 1, S.mode))] }
}

// MARK: - Праздничный сезон

/// Украшения работают с 1 ноября по 15 января.
func inSeason(_ d: Date = Date()) -> Bool {
    let c = Calendar.current.dateComponents([.month, .day], from: d)
    return c.month == 11 || c.month == 12 || (c.month == 1 && (c.day ?? 1) <= 15)
}

func nextNewYear(after d: Date = Date()) -> Date {
    let cal = Calendar.current
    let y = cal.component(.year, from: d)
    return cal.date(from: DateComponents(year: y + 1, month: 1, day: 1))!
}

func isNewYearHolidays(_ d: Date = Date()) -> Bool {
    let c = Calendar.current.dateComponents([.month, .day], from: d)
    return c.month == 1 && (c.day ?? 1) <= 15
}

// MARK: - Звуки

enum Sound {
    static var last: [String: Double] = [:]
    static func play(_ name: String, volume: Float = 0.4, minGap: Double = 0.08) {
        guard S.sounds else { return }
        let now = CACurrentMediaTime()
        if let l = last[name], now - l < minGap { return }
        last[name] = now
        if let s = NSSound(named: NSSound.Name(name))?.copy() as? NSSound {
            s.volume = volume
            s.play()
        }
    }
}

// MARK: - Картинки

/// Мягкая круглая снежинка/искра.
func makeFlakeImage() -> CGImage {
    let s = 32
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Белая серединка и лёгкий голубовато-серый ореол, чтобы снежинки были видны на белом фоне.
    let colors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.95),
        CGColor(red: 0.75, green: 0.8, blue: 0.9, alpha: 0.45),
        CGColor(red: 0.6, green: 0.65, blue: 0.75, alpha: 0),
    ] as CFArray
    let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.4, 0.62, 1])!
    let c = CGPoint(x: s / 2, y: s / 2)
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(s) / 2, options: [])
    return ctx.makeImage()!
}

/// Рисует картинку размером w×h (в точках, с ретина-плотностью) через AppKit.
func drawImage(width w: CGFloat, height h: CGFloat, flip: Bool = false, _ draw: () -> Void) -> CGImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * 2), pixelsHigh: Int(h * 2),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    if flip {
        let t = NSAffineTransform()
        t.translateX(by: w, yBy: 0)
        t.scaleX(by: -1, yBy: 1)
        t.concat()
    }
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

func emoji(_ s: String, _ size: CGFloat, at p: CGPoint) {
    (s as NSString).draw(at: p, withAttributes: [.font: NSFont.systemFont(ofSize: size)])
}

func emojiImage(_ s: String, size: CGFloat) -> CGImage {
    drawImage(width: size * 1.25, height: size * 1.25) { emoji(s, size, at: .zero) }
}
