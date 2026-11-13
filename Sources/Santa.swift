// Санта на оленях пролетает по экрану и роняет подарки. Подарки можно ловить курсором.

import Cocoa
import QuartzCore

final class Santa {
    unowned let snow: SnowController
    unowned let fireworks: Fireworks
    var flight: Flight?
    var gifts: [Gift] = []
    var nextVisit = CACurrentMediaTime() + rndD(120, 300)   // первый визит — через 2–5 минут
    var onCaught: (() -> Void)?

    lazy var leftImage = Santa.sleighImage(flip: false)    // олени смотрят влево — летим влево
    lazy var rightImage = Santa.sleighImage(flip: true)
    lazy var giftImage = emojiImage("🎁", size: 24)

    struct Flight {
        let layer: CALayer
        let trail: CAEmitterLayer
        let overlay: OverlayWindow
        let dir: CGFloat
        var x: CGFloat
        let y0: CGFloat
        let speed: CGFloat
        var t: Double
        var nextDrop: Double
    }

    final class Gift {
        let layer: CALayer
        let overlay: OverlayWindow
        var x, y, vx, vy: CGFloat           // глобальные координаты центра
        var landed: (pile: Int, col: Int, at: Double)?
        let phase = rndD(0, 6)
        init(layer: CALayer, overlay: OverlayWindow, x: CGFloat, y: CGFloat, vx: CGFloat) {
            self.layer = layer; self.overlay = overlay; self.x = x; self.y = y; self.vx = vx; self.vy = 0
        }
    }

    init(snow: SnowController, fireworks: Fireworks) {
        self.snow = snow
        self.fireworks = fireworks
    }

    static func sleighImage(flip: Bool) -> CGImage {
        let s: CGFloat = 42
        return drawImage(width: s * 3.4, height: s * 1.6, flip: flip) {
            // вожжи
            let reins = NSBezierPath()
            reins.move(to: NSPoint(x: s * 0.7, y: s * 0.85))
            reins.curve(to: NSPoint(x: s * 2.15, y: s * 0.6),
                        controlPoint1: NSPoint(x: s * 1.2, y: s * 0.55), controlPoint2: NSPoint(x: s * 1.7, y: s * 0.5))
            NSColor(calibratedRed: 0.55, green: 0.3, blue: 0.12, alpha: 1).setStroke()
            reins.lineWidth = 1.5
            reins.stroke()
            emoji("🦌", s, at: NSPoint(x: 0, y: s * 0.2))
            emoji("🦌", s, at: NSPoint(x: s * 0.95, y: s * 0.2))
            emoji("🎅", s * 0.8, at: NSPoint(x: s * 2.25, y: s * 0.55))
            emoji("🛷", s * 1.15, at: NSPoint(x: s * 1.95, y: 0))
        }
    }

    func call() {
        guard flight == nil, snow.enabled else { return }
        nextVisit = 0
    }

    func tick(now: Double, dt: CGFloat) {
        if flight == nil && S.santa && now >= nextVisit { startFlight(now: now) }
        updateFlight(now: now, dt: dt)
        updateGifts(now: now, dt: dt)
    }

    func startFlight(now: Double) {
        guard let o = snow.overlays.randomElement() else { return }
        let b = o.fxLayer.bounds
        let dir: CGFloat = Bool.random() ? -1 : 1
        let img = dir < 0 ? leftImage : rightImage
        let size = CGSize(width: CGFloat(img.width) / 2, height: CGFloat(img.height) / 2)
        let layer = CALayer()
        layer.contents = img
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.contentsScale = 2

        // Золотой шлейф за санями.
        let trail = CAEmitterLayer()
        trail.frame = b
        trail.emitterShape = .point
        trail.renderMode = .additive
        let c = CAEmitterCell()
        c.contents = snow.flake
        c.birthRate = 70
        c.lifetime = 1.6
        c.lifetimeRange = 0.6
        c.velocity = 20
        c.velocityRange = 15
        c.emissionRange = .pi * 2
        c.yAcceleration = -25
        c.scale = 0.1
        c.scaleRange = 0.05
        c.alphaSpeed = -0.6
        c.color = CGColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
        trail.emitterCells = [c]
        trail.beginTime = o.fxLayer.convertTime(CACurrentMediaTime(), from: nil)
        o.fxLayer.addSublayer(trail)
        o.fxLayer.addSublayer(layer)

        let x = dir < 0 ? b.width + size.width : -size.width
        flight = Flight(layer: layer, trail: trail, overlay: o, dir: dir, x: x,
                        y0: b.height * rnd(0.6, 0.8), speed: 150, t: 0, nextDrop: now + rndD(0.8, 1.5))
        Sound.play("Purr", volume: 0.3)
    }

    func updateFlight(now: Double, dt: CGFloat) {
        guard var f = flight else { return }
        f.t += Double(dt)
        f.x += f.dir * f.speed * dt
        let y = f.y0 + CGFloat(sin(f.t * 1.6)) * 14
        let w = f.layer.bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        f.layer.position = CGPoint(x: f.x, y: y)
        f.layer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(cos(f.t * 1.6)) * 0.05 * f.dir))
        f.trail.emitterPosition = CGPoint(x: f.x - f.dir * w * 0.35, y: y - 6)   // хвост за санями
        CATransaction.commit()

        let width = f.overlay.fxLayer.bounds.width
        if S.santa && now >= f.nextDrop && f.x > 40 && f.x < width - 40 {
            f.nextDrop = now + rndD(1.0, 2.2)
            dropGift(from: CGPoint(x: f.x + f.dir * w * 0.25, y: y - 10), overlay: f.overlay, vx: f.dir * f.speed * 0.3)
        }
        if (f.dir < 0 && f.x < -w) || (f.dir > 0 && f.x > width + w) {
            f.layer.removeFromSuperlayer()
            f.trail.birthRate = 0
            let trail = f.trail
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { trail.removeFromSuperlayer() }
            flight = nil
            nextVisit = now + rndD(2400, 4200)   // следующий визит через 40–70 минут
            return
        }
        flight = f
    }

    func dropGift(from local: CGPoint, overlay o: OverlayWindow, vx: CGFloat) {
        guard gifts.count < 30 else { return }
        let l = CALayer()
        l.contents = giftImage
        l.bounds = CGRect(x: 0, y: 0, width: 30, height: 30)
        l.contentsScale = 2
        o.giftLayer.addSublayer(l)
        let g = Gift(layer: l, overlay: o, x: local.x + o.screenFrame.minX, y: local.y + o.screenFrame.minY, vx: vx)
        place(g)
        gifts.append(g)
    }

    func place(_ g: Gift) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        g.layer.position = g.overlay.toLocal(CGPoint(x: g.x, y: g.y))
        CATransaction.commit()
    }

    func updateGifts(now: Double, dt: CGFloat) {
        guard !gifts.isEmpty else { return }
        let m = NSEvent.mouseLocation
        var keep: [Gift] = []
        for g in gifts {
            // Поймали курсором?
            if hypot(m.x - g.x, m.y - g.y) < 22 {
                catchGift(g)
                continue
            }
            if let land = g.landed {
                // Лежит на сугробе: едет вместе с окном, падает, если снег сбили.
                if let p = snow.piles[land.pile], snow.order.contains(land.pile), land.col < p.count,
                   p.visible[land.col] {
                    g.x = p.x(land.col)
                    g.y = p.surface(land.col) + 12
                    if now - land.at > 25 { fadeOut(g); continue }
                } else {
                    g.landed = nil
                }
            } else {
                let oy = g.y - 12
                g.vy += (-150 - g.vy) * min(1, dt * 1.5)     // «парашютик»: падает плавно
                g.vx *= pow(0.5, dt)
                g.x += g.vx * dt + CGFloat(sin(now * 3 + g.phase)) * 14 * dt
                g.y += g.vy * dt
                if let (p, i) = snow.surfaceHit(x: g.x, from: oy, to: g.y - 12) {
                    g.landed = (p.id, i, now)
                    g.y = p.surface(i) + 12
                }
                if g.y < g.overlay.screenFrame.minY - 40 || !g.overlay.screenFrame.insetBy(dx: -60, dy: -200).contains(CGPoint(x: g.x, y: g.y)) {
                    g.layer.removeFromSuperlayer()
                    continue
                }
            }
            place(g)
            keep.append(g)
        }
        gifts = keep
    }

    func catchGift(_ g: Gift) {
        fireworks.sparkle(at: CGPoint(x: g.x, y: g.y))
        Sound.play("Glass", volume: 0.4)
        S.giftsCaught += 1
        onCaught?()
        let anim = CABasicAnimation(keyPath: "transform.scale")
        anim.toValue = 1.8
        anim.duration = 0.25
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.toValue = 0
        fade.duration = 0.25
        g.layer.add(anim, forKey: nil)
        g.layer.add(fade, forKey: nil)
        g.layer.opacity = 0
        let l = g.layer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { l.removeFromSuperlayer() }
    }

    func fadeOut(_ g: Gift) {
        g.layer.opacity = 0   // неявная анимация растворения
        let l = g.layer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { l.removeFromSuperlayer() }
    }
}
