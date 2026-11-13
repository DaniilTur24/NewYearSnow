// Салют: двойной клик по пустому рабочему столу, новогоднее шоу в полночь, искры.

import Cocoa
import QuartzCore

final class Fireworks {
    unowned let snow: SnowController
    var monitor: Any?
    var showTimer: Timer?

    static let palette: [CGColor] = [
        CGColor(red: 1, green: 0.25, blue: 0.3, alpha: 1),
        CGColor(red: 1, green: 0.8, blue: 0.25, alpha: 1),
        CGColor(red: 0.3, green: 1, blue: 0.5, alpha: 1),
        CGColor(red: 0.35, green: 0.65, blue: 1, alpha: 1),
        CGColor(red: 1, green: 0.45, blue: 0.95, alpha: 1),
        CGColor(red: 0.6, green: 1, blue: 1, alpha: 1),
        CGColor(red: 1, green: 0.6, blue: 0.2, alpha: 1),
    ]
    static let gold = [CGColor(red: 1, green: 0.85, blue: 0.35, alpha: 1), CGColor(red: 1, green: 1, blue: 0.8, alpha: 1)]

    init(snow: SnowController) { self.snow = snow }

    func start() {
        // Глобальный монитор мыши не требует особых разрешений.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
            guard e.clickCount == 2 else { return }
            let p = NSEvent.mouseLocation
            MainActor.assumeIsolated { self?.doubleClick(at: p) }
        }
    }

    func doubleClick(at p: CGPoint) {
        guard S.fireworks, snow.enabled, snow.isEmptyDesktop(p) else { return }
        launch(to: p)
    }

    func overlay(at p: CGPoint) -> OverlayWindow? { snow.overlays.first { $0.screenFrame.contains(p) } }

    func now(_ layer: CALayer) -> CFTimeInterval { layer.convertTime(CACurrentMediaTime(), from: nil) }

    /// Ракета взлетает снизу к точке p (глобальные координаты) и взрывается.
    func launch(to p: CGPoint, colors: [CGColor]? = nil) {
        guard let o = overlay(at: p) else { return }
        let target = o.toLocal(p)
        let start = CGPoint(x: target.x + rnd(-70, 70), y: 0)
        let trail = CAEmitterLayer()
        trail.frame = o.fxLayer.bounds
        trail.emitterShape = .point
        trail.renderMode = .additive
        trail.emitterPosition = start
        let c = CAEmitterCell()
        c.contents = snow.flake
        c.birthRate = 180
        c.lifetime = 0.6
        c.lifetimeRange = 0.3
        c.velocity = 25
        c.velocityRange = 15
        c.emissionRange = .pi * 2
        c.scale = 0.12
        c.scaleSpeed = -0.15
        c.alphaSpeed = -1.6
        c.yAcceleration = -60
        c.color = CGColor(red: 1, green: 0.85, blue: 0.55, alpha: 1)
        trail.emitterCells = [c]
        trail.beginTime = now(o.fxLayer)
        o.fxLayer.addSublayer(trail)

        let dur = 0.7 + Double(target.y) / 1600
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            trail.birthRate = 0
            self?.burst(at: target, in: o, colors: colors)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { trail.removeFromSuperlayer() }
        }
        let anim = CABasicAnimation(keyPath: "emitterPosition")
        anim.fromValue = NSValue(point: start)
        anim.toValue = NSValue(point: target)
        anim.duration = dur
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        trail.emitterPosition = target
        trail.add(anim, forKey: "fly")
        CATransaction.commit()
        Sound.play("Blow", volume: 0.12, minGap: 0.15)
    }

    /// Взрыв салюта в точке (локальные координаты оверлея).
    func burst(at p: CGPoint, in o: OverlayWindow, colors: [CGColor]? = nil, power: CGFloat = 1) {
        let e = CAEmitterLayer()
        e.frame = o.fxLayer.bounds
        e.emitterPosition = p
        e.emitterShape = .point
        e.renderMode = .additive
        let cols = colors ?? Array(Fireworks.palette.shuffled().prefix(2))
        var cells: [CAEmitterCell] = cols.map { col in
            let c = CAEmitterCell()
            c.contents = snow.flake
            c.birthRate = Float(2500 * power)
            c.lifetime = Float(1.4 + 0.6 * power)
            c.lifetimeRange = 0.5
            c.velocity = rnd(150, 210) * power
            c.velocityRange = 50 * power
            c.emissionRange = .pi * 2
            c.yAcceleration = -110
            c.scale = 0.13
            c.scaleRange = 0.05
            c.scaleSpeed = -0.05
            c.alphaSpeed = -0.5
            c.color = col
            return c
        }
        let glitter = CAEmitterCell()   // мерцающие белые искорки
        glitter.contents = snow.flake
        glitter.birthRate = Float(600 * power)
        glitter.lifetime = 2.4
        glitter.lifetimeRange = 0.8
        glitter.velocity = 90 * power
        glitter.velocityRange = 60 * power
        glitter.emissionRange = .pi * 2
        glitter.yAcceleration = -60
        glitter.scale = 0.06
        glitter.alphaRange = 0.6
        glitter.alphaSpeed = -0.35
        glitter.color = CGColor(red: 1, green: 1, blue: 0.9, alpha: 1)
        cells.append(glitter)
        e.emitterCells = cells
        e.beginTime = now(o.fxLayer)
        o.fxLayer.addSublayer(e)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { e.birthRate = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { e.removeFromSuperlayer() }
        if power >= 1 { Sound.play("Pop", volume: 0.3, minGap: 0.05) }
    }

    /// Маленький золотой всплеск (глобальные координаты).
    func sparkle(at p: CGPoint) {
        guard let o = overlay(at: p) else { return }
        burst(at: o.toLocal(p), in: o, colors: Fireworks.gold, power: 0.35)
    }

    /// Новогоднее шоу: надпись и салют по всем экранам.
    func grandShow(duration: Double = 40) {
        showTimer?.invalidate()
        for o in snow.overlays { showGreeting(in: o, duration: duration) }
        let end = CACurrentMediaTime() + duration
        let t = Timer(timeInterval: 0.35, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, CACurrentMediaTime() < end else { timer.invalidate(); return }
                guard let o = self.snow.overlays.randomElement() else { return }
                let f = o.screenFrame
                self.launch(to: CGPoint(x: f.minX + rnd(f.width * 0.08, f.width * 0.92),
                                        y: f.minY + rnd(f.height * 0.4, f.height * 0.85)))
            }
        }
        RunLoop.main.add(t, forMode: .common)
        showTimer = t
        Sound.play("Hero", volume: 0.4)
    }

    func showGreeting(in o: OverlayWindow, duration: Double) {
        let text = CATextLayer()
        text.string = "С Новым годом! 🎄"
        text.font = NSFont.systemFont(ofSize: 72, weight: .heavy)
        text.fontSize = 72
        text.alignmentMode = .center
        text.foregroundColor = .white
        text.contentsScale = 2
        text.shadowColor = CGColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
        text.shadowOpacity = 0.9
        text.shadowRadius = 12
        text.shadowOffset = .zero
        let b = o.fxLayer.bounds
        text.frame = CGRect(x: 0, y: b.height * 0.55, width: b.width, height: 100)
        text.opacity = 0
        o.fxLayer.addSublayer(text)

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.08, 0.85, 1]
        fade.duration = duration
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 0.96
        pulse.toValue = 1.04
        pulse.duration = 1.2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        text.add(fade, forKey: "fade")
        text.add(pulse, forKey: "pulse")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { text.removeFromSuperlayer() }
    }
}
