// Прозрачное окно-оверлей на каждый монитор и гирлянда.

import Cocoa
import QuartzCore

final class OverlayWindow: NSWindow {
    let screenFrame: CGRect
    let emitter = CAEmitterLayer()        // густой снег — только там, где нет окон
    let windowEmitter = CAEmitterLayer()  // редкий и прозрачный снег — поверх окон
    let clearArea = CAShapeLayer()        // маска: пустой стол
    let windowArea = CAShapeLayer()       // маска: открытые окна
    let pileLayer = CAShapeLayer()
    let icicleLayer = CAShapeLayer()
    let icicleShine = CAShapeLayer()
    let chunkLayer = CAShapeLayer()
    let puffLayer = CAShapeLayer()
    let giftLayer = CALayer()
    let fxLayer = CALayer()               // салют, Санта
    let garland: Garland        // сверху, свисает
    let garlandLow: Garland     // снизу, лежит на сугробе

    init(screen: NSScreen, flake: CGImage) {
        screenFrame = screen.frame
        garland = Garland(screen: screen, place: .top)
        garlandLow = Garland(screen: screen, place: .bottom)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true                 // клики проходят насквозь
        level = .statusBar                        // поверх обычных окон и строки меню
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        setFrame(screen.frame, display: false)

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        contentView = view
        let root = view.layer!
        let w = screen.frame.width, h = screen.frame.height
        let edge = CGColor(red: 0.78, green: 0.84, blue: 0.93, alpha: 1)

        // Сугробы
        pileLayer.fillColor = .white
        pileLayer.strokeColor = edge
        pileLayer.lineWidth = 0.75
        pileLayer.shadowColor = CGColor(red: 0.25, green: 0.35, blue: 0.55, alpha: 1)
        pileLayer.shadowOpacity = 0.35
        pileLayer.shadowRadius = 1.5
        pileLayer.shadowOffset = CGSize(width: 0, height: -1)

        // Сосульки
        // Полупрозрачный лёд с тонкой голубой кромкой и белым бликом.
        icicleLayer.fillColor = CGColor(red: 0.8, green: 0.91, blue: 1, alpha: 0.7)
        icicleLayer.strokeColor = CGColor(red: 0.48, green: 0.66, blue: 0.9, alpha: 0.85)
        icicleLayer.lineWidth = 0.6
        icicleLayer.shadowColor = CGColor(red: 0.2, green: 0.35, blue: 0.6, alpha: 1)
        icicleLayer.shadowOpacity = 0.2
        icicleLayer.shadowRadius = 0.8
        icicleLayer.shadowOffset = CGSize(width: 0.5, height: -0.5)
        icicleShine.fillColor = nil
        icicleShine.strokeColor = CGColor(gray: 1, alpha: 0.9)
        icicleShine.lineWidth = 0.8
        icicleShine.lineCap = .round

        // Летящие комки и снежная пыль
        chunkLayer.fillColor = .white
        chunkLayer.strokeColor = edge
        chunkLayer.lineWidth = 0.5
        puffLayer.fillColor = CGColor(gray: 1, alpha: 0.9)

        for l in [pileLayer, icicleLayer, icicleShine, chunkLayer, puffLayer] as [CALayer] {
            l.frame = root.bounds
            root.addSublayer(l)
        }

        // Падающий снег
        func cell(_ name: String, scale: CGFloat, scaleRange: CGFloat, vel: CGFloat, velRange: CGFloat, birth: CGFloat) -> CAEmitterCell {
            let c = CAEmitterCell()
            c.name = name
            c.contents = flake
            c.birthRate = Float(birth)
            c.lifetime = Float(h / (vel - velRange) + 6)
            c.velocity = vel
            c.velocityRange = velRange
            c.emissionLongitude = -.pi / 2       // вниз (у слоёв на macOS ось y смотрит вверх)
            c.emissionRange = .pi / 9
            c.xAcceleration = 5
            c.yAcceleration = -3
            c.scale = scale
            c.scaleRange = scaleRange
            c.alphaRange = 0.35
            return c
        }
        for e in [windowEmitter, emitter] {
            e.frame = root.bounds
            e.emitterShape = .line
            e.emitterPosition = CGPoint(x: w / 2, y: h + 20)
            e.emitterSize = CGSize(width: w * 1.5, height: 1)
            e.renderMode = .unordered
            e.emitterCells = [
                cell("small", scale: 0.16, scaleRange: 0.06, vel: 42, velRange: 18, birth: w / 40),  // мелкие, дальние
                cell("big", scale: 0.32, scaleRange: 0.10, vel: 75, velRange: 25, birth: w / 220),   // крупные, ближние
            ]
            root.addSublayer(e)
        }
        clearArea.frame = root.bounds
        clearArea.fillColor = .white
        clearArea.path = CGPath(rect: root.bounds, transform: nil)
        emitter.mask = clearArea
        windowArea.frame = root.bounds
        windowArea.fillColor = CGColor(gray: 1, alpha: 0.1)
        windowEmitter.mask = windowArea

        for g in [garland, garlandLow] {
            g.layer.frame = root.bounds
            root.addSublayer(g.layer)
        }
        for l in [giftLayer, fxLayer] {
            l.frame = root.bounds
            root.addSublayer(l)
        }
    }

    func toLocal(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - screenFrame.minX, y: p.y - screenFrame.minY) }
}

// MARK: - Гирлянды: сверху висит, снизу лежит на сугробе

final class Garland {
    enum Place { case top, bottom }

    let place: Place
    let layer = CALayer()
    let wire = CAShapeLayer()
    var bulbs: [CAShapeLayer] = []
    var phases: [Double] = []
    let size: CGSize
    let notch: (CGFloat, CGFloat)?        // вырез («чёлка») MacBook — для верхней
    var ground: ((CGFloat) -> CGFloat)?   // для нижней: на какой высоте лежит провод в точке x (снег, Док)
    var noBulbs: [(CGFloat, CGFloat)] = []   // где лампочек нет (провод забирается на Док)

    static let colors: [CGColor] = [
        CGColor(red: 1, green: 0.2, blue: 0.22, alpha: 1),    // красный
        CGColor(red: 1, green: 0.78, blue: 0.15, alpha: 1),   // золотой
        CGColor(red: 0.2, green: 0.88, blue: 0.4, alpha: 1),  // зелёный
        CGColor(red: 0.25, green: 0.55, blue: 1, alpha: 1),   // синий
        CGColor(red: 1, green: 0.38, blue: 0.85, alpha: 1),   // розовый
        CGColor(red: 1, green: 0.52, blue: 0.1, alpha: 1),    // оранжевый
    ]

    init(screen: NSScreen, place: Place) {
        let f = screen.frame
        self.place = place
        size = f.size
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notch = (l.maxX - f.minX, r.minX - f.minX)
        } else {
            notch = nil
        }
        layer.frame = CGRect(origin: .zero, size: size)
        build()
    }

    /// Участки провода по x (верхняя обходит вырез экрана, нижняя идёт непрерывно).
    var spans: [(CGFloat, CGFloat)] {
        guard place == .top, let h = notch else { return [(0, size.width)] }
        return [(0, h.0 - 6), (h.1 + 6, size.width)]
    }

    /// Нижняя гирлянда: задать рельеф, по которому она лежит, и перестроить.
    func setGround(_ g: @escaping (CGFloat) -> CGFloat, noBulbs: [(CGFloat, CGFloat)]) {
        ground = g
        self.noBulbs = noBulbs
        build()
    }

    /// Собрать гирлянду заново (размер — из настроек).
    func build() {
        let u = CGFloat(S.garlandSize)
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        bulbs = []
        phases = []

        wire.strokeColor = CGColor(red: 0.08, green: 0.18, blue: 0.1, alpha: 0.95)
        wire.fillColor = nil
        wire.lineWidth = 0.8 + 0.4 * u
        wire.lineCap = .round
        wire.lineJoin = .round
        layer.addSublayer(wire)

        // Форма лампочки: из точки крепления (0,0) вниз. Для нижней гирлянды переворачиваем — смотрит вверх.
        let socket = CGPath(roundedRect: CGRect(x: -1.1 * u, y: -1.9 * u, width: 2.2 * u, height: 2.1 * u),
                            cornerWidth: 0.4 * u, cornerHeight: 0.4 * u, transform: nil)
        let bulb = CGMutablePath()
        bulb.move(to: CGPoint(x: -1.0 * u, y: -1.6 * u))
        bulb.addCurve(to: CGPoint(x: 0, y: -8.1 * u), control1: CGPoint(x: -2.7 * u, y: -3.3 * u),
                      control2: CGPoint(x: -1.5 * u, y: -7.3 * u))
        bulb.addCurve(to: CGPoint(x: 1.0 * u, y: -1.6 * u), control1: CGPoint(x: 1.5 * u, y: -7.3 * u),
                      control2: CGPoint(x: 2.7 * u, y: -3.3 * u))
        bulb.closeSubpath()
        let shine = CGPath(ellipseIn: CGRect(x: -1.25 * u, y: -4.6 * u, width: 0.7 * u, height: 1.9 * u), transform: nil)

        func addBulb(at p: CGPoint, angle: CGFloat) {
            let color = Garland.colors[bulbs.count % Garland.colors.count]
            let holder = CALayer()
            holder.position = p
            holder.bounds = .zero
            holder.setAffineTransform(CGAffineTransform(rotationAngle: angle))
            let glass = CAShapeLayer()
            glass.path = bulb
            glass.fillColor = color
            glass.shadowColor = color
            glass.shadowPath = bulb
            glass.shadowRadius = 2 + 2.2 * u
            glass.shadowOffset = .zero
            glass.shadowOpacity = 0.9
            let hl = CAShapeLayer()
            hl.path = shine
            hl.fillColor = CGColor(gray: 1, alpha: 0.55)
            glass.addSublayer(hl)
            let cap = CAShapeLayer()
            cap.path = socket
            cap.fillColor = CGColor(red: 0.12, green: 0.24, blue: 0.14, alpha: 1)
            holder.addSublayer(glass)
            holder.addSublayer(cap)
            layer.addSublayer(holder)
            phases.append(Double(bulbs.count) * 0.7)
            bulbs.append(glass)
        }

        let path = CGMutablePath()
        let spacing = 10 + 8 * u
        for (a, b) in spans where b - a > 30 {
            switch place {
            case .top:
                // Провод провисает между крючками, лампочки свисают вниз.
                let top = size.height - 0.5
                let sag = 2.5 + 2.2 * u
                let hooks = max(1, Int((b - a) / 120))
                let seg = (b - a) / CGFloat(hooks)
                for k in 0..<hooks {
                    let x0 = a + CGFloat(k) * seg, x1 = x0 + seg
                    let ctrl = CGPoint(x: (x0 + x1) / 2, y: top - 2 * sag)
                    path.move(to: CGPoint(x: x0, y: top))
                    path.addQuadCurve(to: CGPoint(x: x1, y: top), control: ctrl)
                    let count = max(1, Int(seg / spacing))
                    for j in 0..<count {
                        let t = (CGFloat(j) + 0.5) / CGFloat(count)
                        let x = x0 + (x1 - x0) * t
                        let y = (1 - t) * (1 - t) * top + 2 * t * (1 - t) * ctrl.y + t * t * top
                        let slope = (2 * (1 - t) * (ctrl.y - top) + 2 * t * (top - ctrl.y)) / (x1 - x0)
                        addBulb(at: CGPoint(x: x, y: y), angle: atan(slope) + rnd(-0.22, 0.22))
                    }
                }
            case .bottom:
                // Провод лежит на сугробе (и на Доке) и повторяет рельеф, лампочки торчат вверх вразнобой.
                func y(_ x: CGFloat) -> CGFloat { (ground?(x) ?? 8) - 1.5 + 1.2 * sin(x * 0.05) }
                path.move(to: CGPoint(x: a, y: y(a)))
                var x = a
                while x < b { x = min(b, x + 3); path.addLine(to: CGPoint(x: x, y: y(x))) }
                let count = max(1, Int((b - a) / spacing))
                for j in 0..<count {
                    let x = a + (b - a) * (CGFloat(j) + 0.5) / CGFloat(count)
                    if noBulbs.contains(where: { x > $0.0 && x < $0.1 }) { continue }
                    let slope = (y(x + 2) - y(x - 2)) / 4
                    addBulb(at: CGPoint(x: x, y: y(x)), angle: .pi + atan(slope) + rnd(-0.38, 0.38))
                }
            }
        }
        wire.path = path
    }

    /// Режимы: 0 — переливы, 1 — бегущие огни, 2 — мерцание, 3 — всегда горят.
    func update(time t: Double, mode: Int) {
        for (i, b) in bulbs.enumerated() {
            let v: Double
            switch mode {
            case 0: v = 0.5 + 0.5 * sin(t * 2.2 + phases[i])
            case 1: v = (i + Int(t * 8)) % 4 == 0 ? 1 : 0.12
            case 2: v = sin(t * 5.3 + phases[i] * 13.1) > 0.55 ? 1 : 0.3
            default: v = 1
            }
            b.opacity = Float(0.3 + 0.7 * v)
            b.shadowOpacity = Float(v)
        }
    }
}
