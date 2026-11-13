// Вся логика снега: окна, Док, вкладки, мышь, физика, снеговики и отрисовка.

import Cocoa
import QuartzCore

/// Снимок настроек на один кадр (чтобы не дёргать UserDefaults в горячих циклах).
struct Snap {
    var piles, icicles, cursorWind, bottomSnow, tabSnow, snowing: Bool
    var growSeconds: CGFloat
    static func now() -> Snap {
        Snap(piles: S.piles, icicles: S.icicles, cursorWind: S.cursorWind, bottomSnow: S.bottomSnow,
             tabSnow: S.tabSnow, snowing: S.snowing, growSeconds: WinterMode.current.growSeconds)
    }
}

struct WinEntry {
    let id: Int
    let frame: CGRect
    let kind: PileKind
    let pid: Int32
}

/// Вкладки окна, координаты относительно рамки самого окна.
struct TabScan {
    let windowID: Int
    let rel: [CGRect]
}

final class SnowController {
    var overlays: [OverlayWindow] = []
    var piles: [Int: Pile] = [:]
    var order: [Int] = []          // всё, на чём лежит снег, спереди назад
    var chunks: [Chunk] = []
    var puffs: [Puff] = []
    var fallingIcicles: [FallingIcicle] = []
    var windowFrames: [CGRect] = []
    var lastWins: [WinEntry] = []
    var dockFrame: CGRect?
    var tabScans: [Int: TabScan] = [:]
    var tabScanBusy = false
    var lastTabScan = 0.0
    var lastMouse = NSEvent.mouseLocation
    var lastTick = CACurrentMediaTime()
    var lastPoll = 0.0
    var lastDockPoll = 0.0
    var lastGarland = 0.0
    var growAcc: CGFloat = 0
    var dirty = true
    var particlesOnScreen = false
    var firstPoll = true
    var minY: CGFloat = 0
    var timer: Timer?
    var maskKey: [CGRect] = [CGRect(x: -1, y: -1, width: 0, height: 0)]
    var enabled = true
    var lastGust = 0.0
    var garlandDock: CGRect? = CGRect(x: -1, y: -1, width: 0, height: 0)   // для какого положения Дока построена гирлянда
    var cfg = Snap.now()
    var maskExtras: () -> [CGRect] = { [] }      // наши окна (приветствие), где снег не нужен
    var onTick: ((Double, CGFloat) -> Void)?    // Санта и т. п.
    let myPID = getpid()
    lazy var flake = makeFlakeImage()

    static let ignoredOwners: Set<String> = ["Window Server", "Dock", "Control Center", "Notification Center", "SystemUIServer"]

    func start() {
        buildOverlays()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.buildOverlays() }
        }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func buildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { OverlayWindow(screen: $0, flake: flake) }
        if enabled { overlays.forEach { $0.orderFrontRegardless() } }
        minY = NSScreen.screens.map { $0.frame.minY }.min() ?? 0
        maskKey = [CGRect(x: -1, y: -1, width: 0, height: 0)]
        garlandDock = CGRect(x: -1, y: -1, width: 0, height: 0)
        updateGarlandGaps()
        applyEmitter()
        dirty = true
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        overlays.forEach { on ? $0.orderFrontRegardless() : $0.orderOut(nil) }
        applyEmitter()
        dirty = true
    }

    /// Применить настройки снегопада, ветра и гирлянды к слоям.
    func applyEmitter() {
        let on = S.snowing && enabled
        let mode = WinterMode.current
        let alpha = CGFloat(S.windowAlpha)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for o in overlays {
            o.emitter.birthRate = on ? mode.snowfall : 0
            o.windowEmitter.birthRate = on ? mode.overWindows : 0
            o.windowArea.fillColor = CGColor(gray: 1, alpha: alpha)
            for e in [o.emitter, o.windowEmitter] {
                e.velocity = mode.fallSpeed
                e.scale = mode.flakeSize
            }
            o.garland.layer.isHidden = !S.garland
            o.garlandLow.layer.isHidden = !S.garland
        }
        CATransaction.commit()
        applyWind(now: CACurrentMediaTime())
    }

    /// Ветер: режим + порывы (в «Максимальном» снег то и дело сносит вбок).
    func applyWind(now: Double) {
        let mode = WinterMode.current
        let gust = mode.gusts * CGFloat(sin(now * 0.35) * 0.6 + sin(now * 0.9 + 1.3) * 0.4)
        let x = 5 + mode.wind + gust
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for o in overlays {
            for e in [o.emitter, o.windowEmitter] {
                for n in ["small", "big"] { e.setValue(x, forKeyPath: "emitterCells.\(n).xAcceleration") }
            }
        }
        CATransaction.commit()
    }

    /// Сменить режим: снегопад, высота сугробов и сосульки.
    func applyMode(from old: WinterMode) {
        applyEmitter()
        // Сугробы сразу становятся выше или ниже под новый режим.
        let ratio = WinterMode.current.pileScale / old.pileScale
        for p in piles.values {
            for i in 0..<p.count { p.heights[i] *= ratio }
            p.retarget()
            if p.kind == .window { p.makeIcicles(fill: 0.6) }
        }
        updateGarlandGaps(force: true)   // сугроб внизу стал выше/ниже — гирлянда ложится заново
        dirty = true
    }

    /// Пересчитать «естественную» высоту сугробов (после смены ползунка).
    func retarget() {
        piles.values.forEach { $0.retarget() }
        dirty = true
    }

    // MARK: - Цикл

    func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(now - lastTick, 1.0 / 20))
        lastTick = now
        guard enabled else { return }
        cfg = Snap.now()

        // Пока зажата кнопка мыши (возможно, тащат окно) — опрашиваем окна часто, иначе 10 раз в секунду.
        let pollInterval = NSEvent.pressedMouseButtons != 0 ? 1.0 / 60 : 1.0 / 10
        if now - lastPoll >= pollInterval - 0.002 {
            pollWindows(now: now)
            lastPoll = now
        }
        handleMouse(dt: max(dt, 0.001), now: now)
        growAcc += dt
        if growAcc >= 0.25 { grow(growAcc); growAcc = 0 }
        updateParticles(dt: dt)
        if WinterMode.current.gusts > 0 && now - lastGust >= 0.5 { lastGust = now; applyWind(now: now) }

        if S.garland && now - lastGarland >= 0.05 {
            lastGarland = now
            let mode = S.garlandMode
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for o in overlays { o.garland.update(time: now, mode: mode); o.garlandLow.update(time: now, mode: mode) }
            CATransaction.commit()
        }
        onTick?(now, dt)

        if dirty || hasParticles || particlesOnScreen { render() }
    }

    var hasParticles: Bool { !chunks.isEmpty || !puffs.isEmpty || !fallingIcicles.isEmpty }

    // MARK: - Окна, Док, вкладки

    func pollWindows(now: Double) {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return }
        let screens = NSScreen.screens
        let primaryH = screens.first?.frame.height ?? 0
        var wins: [WinEntry] = []
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? Int32, pid != myPID,
                  let num = w[kCGWindowNumber as String] as? Int,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bd),
                  r.width >= 140, r.height >= 80,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05
            else { continue }
            if let owner = w[kCGWindowOwnerName as String] as? String, Self.ignoredOwners.contains(owner) { continue }
            // Quartz: начало координат сверху слева. Cocoa: снизу слева.
            wins.append(WinEntry(id: num, frame: CGRect(x: r.minX, y: primaryH - r.maxY, width: r.width, height: r.height),
                                 kind: .window, pid: pid))
        }
        lastWins = wins
        windowFrames = wins.map { $0.frame }
        updateSnowMask(windowFrames + maskExtras())

        // Вкладки — сразу перед своим окном (то же место в порядке «спереди назад»).
        if cfg.tabSnow {
            if now - lastTabScan > 1.5 { lastTabScan = now; startTabScan(primaryH: primaryH) }
            let ids = Set(wins.map { $0.id })
            tabScans = tabScans.filter { ids.contains($0.key) }
            var out: [WinEntry] = []
            for e in wins {
                if let scan = tabScans[e.id] {
                    for (k, r) in scan.rel.enumerated() {
                        out.append(WinEntry(id: tabPileID(window: e.id, index: k),
                                            frame: r.offsetBy(dx: e.frame.minX, dy: e.frame.minY), kind: .tab, pid: e.pid))
                    }
                }
                out.append(e)
            }
            wins = out
        } else {
            tabScans = [:]
        }

        // Док — поверх всех окон, поэтому идёт первым.
        if now - lastDockPoll >= 1 { pollDock(primaryH: primaryH); lastDockPoll = now; updateGarlandGaps() }
        if let df = dockFrame { wins.insert(WinEntry(id: dockPileID, frame: df, kind: .dock, pid: 0), at: 0) }

        // Сугроб по нижнему краю экрана — позади всего.
        if cfg.bottomSnow {
            for (i, s) in screens.enumerated() {
                wins.append(WinEntry(id: bottomPileID(i),
                                     frame: CGRect(x: s.frame.minX, y: s.frame.minY - 10, width: s.frame.width, height: 10),
                                     kind: .bottom, pid: 0))
            }
        }

        let dtPoll = CGFloat(max(now - lastPoll, 1.0 / 60))
        var newOrder: [Int] = []
        for e in wins {
            newOrder.append(e.id)
            let f = e.frame
            if let p = piles[e.id] {
                if p.frame != f {
                    let sizeChanged = abs(f.width - p.frame.width) > 0.5
                    let v = CGVector(dx: (f.minX - p.frame.minX) / dtPoll, dy: (f.maxY - p.frame.maxY) / dtPoll)
                    p.frame = f
                    if sizeChanged {
                        p.rebuild(keep: true, fill: 0)
                    } else if e.kind == .window && hypot(v.dx, v.dy) > shakeSpeed && p.lastSeen > now - 0.5 {
                        shake(p, velocity: v)     // резко дёрнули окно — снег слетает
                    }
                    dirty = true
                }
            } else {
                let fill: CGFloat
                switch e.kind {
                case .window: fill = firstPoll ? 0.85 : 0.15
                case .dock: fill = 0.85
                case .bottom, .tab: fill = 0.6
                }
                piles[e.id] = Pile(id: e.id, kind: e.kind, frame: f, fill: fill)
                dirty = true
            }
            piles[e.id]!.lastSeen = now
        }
        if newOrder != order { dirty = true }
        order = newOrder
        firstPoll = false
        piles = piles.filter { now - $0.value.lastSeen < forgetAfter }

        // Какие колонки не перекрыты тем, что спереди.
        var fronts: [CGRect] = []
        for e in wins {
            let p = piles[e.id]!
            let f = e.frame
            var hidden = false
            var newScale: CGFloat = 1
            if e.kind == .window || e.kind == .tab {
                let topCenter = CGPoint(x: f.midX, y: f.maxY - 1)
                let scr = screens.first { $0.frame.contains(topCenter) }
                hidden = scr.map { f.maxY >= $0.frame.maxY - 2 } ?? true   // полноэкранное окно
                // Окно, развёрнутое под строку меню: сугроб пониже, чтобы не закрыть текст меню.
                if e.kind == .window, let scr, f.maxY >= scr.visibleFrame.maxY - 2 { newScale = 0.45 }
            }
            if p.scale != newScale { p.scale = newScale; dirty = true }

            if e.kind == .bottom {
                let front = fronts.filter { $0.minY <= f.maxY + 30 }
                for i in 0..<p.count {
                    let x = p.x(i)
                    var vis = true
                    for fr in front where fr.minX - 2 <= x && x <= fr.maxX + 2 { vis = false; break }
                    if p.visible[i] != vis { p.visible[i] = vis; dirty = true }
                }
            } else {
                let front = fronts.filter { $0.minY <= f.maxY + 30 && $0.maxY >= f.maxY - 4 && $0.minX <= f.maxX && $0.maxX >= f.minX }
                for i in 0..<p.count {
                    var vis = !hidden
                    if vis {
                        let x = p.x(i)
                        let a = CGPoint(x: x, y: f.maxY + 3), b = CGPoint(x: x, y: f.maxY - 3)
                        for fr in front where fr.contains(a) || fr.contains(b) { vis = false; break }
                    }
                    if p.visible[i] != vis { p.visible[i] = vis; dirty = true }
                }
            }
            if e.kind != .tab { fronts.append(f) }
        }
    }

    /// Рамка панели Дока через Accessibility API (нужно разрешение «Универсальный доступ»).
    func pollDock(primaryH: CGFloat) {
        guard AXIsProcessTrusted() else {
            // Доступа нет (например, сразу после обновления) — берём последнее запомненное положение Дока.
            dockFrame = DockCache.load()
            return
        }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { dockFrame = nil; return }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.2)
        for c in AX.children(app) where AX.role(c) == (kAXListRole as String) {
            guard let f = AX.frame(c, primaryH: primaryH), f.width > f.height else { continue }  // Док сбоку — не кладём
            dockFrame = f
            DockCache.save(f)
            return
        }
        dockFrame = nil
    }

    /// Гирлянда внизу обходит Док: перестраиваем её, когда Док меняет размер или положение.
    func updateGarlandGaps(force: Bool = false) {
        guard force || dockFrame != garlandDock else { return }
        garlandDock = dockFrame
        for (i, o) in overlays.enumerated() {
            // Профиль сугроба внизу этого экрана — по нему лежит нижняя гирлянда.
            let w = o.screenFrame.width
            let floor = Pile(id: bottomPileID(i), kind: .bottom, frame: CGRect(x: 0, y: -10, width: w, height: 10), fill: 0)
            guard let d = dockFrame, d.minX < o.screenFrame.maxX, d.maxX > o.screenFrame.minX,
                  d.minY < o.screenFrame.minY + 150, d.maxY > o.screenFrame.minY else {
                o.garlandLow.setGround({ x in floor.target(local: x, width: w) }, noBulbs: [])
                continue
            }
            // Док в координатах экрана; провод забирается на него, лежит на снегу на крыше и спускается.
            let l = d.minX - o.screenFrame.minX, r = d.maxX - o.screenFrame.minX
            let roof = d.maxY - o.screenFrame.minY
            let dockSnow = Pile(id: dockPileID, kind: .dock, frame: CGRect(x: l, y: 0, width: r - l, height: 1), fill: 0)
            let ramp: CGFloat = 18
            func floorH(_ x: CGFloat) -> CGFloat {
                var h = floor.target(local: x, width: w)
                let dist = x < l ? l - x : x - r            // у Дока сугроб сходит на нет
                if dist < 36 { h *= sqrt(max(0, dist) / 36) }
                return h
            }
            func roofH(_ x: CGFloat) -> CGFloat {
                roof + dockSnow.target(local: x - l, width: r - l)
            }
            func smooth(_ t: CGFloat) -> CGFloat { let c = min(1, max(0, t)); return c * c * (3 - 2 * c) }
            o.garlandLow.setGround({ x in
                if x <= l - ramp || x >= r + ramp { return floorH(x) }
                if x >= l + ramp && x <= r - ramp { return roofH(x) }
                let t = x < (l + r) / 2 ? smooth((x - (l - ramp)) / (2 * ramp)) : smooth(((r + ramp) - x) / (2 * ramp))
                let a = x < (l + r) / 2 ? l - ramp : r + ramp, b = x < (l + r) / 2 ? l + ramp : r - ramp
                return floorH(a) + (roofH(b) - floorH(a)) * t
            }, noBulbs: [(l - ramp - 4, l + ramp + 4), (r - ramp - 4, r + ramp + 4)])
        }
    }

    /// Ищем вкладки в окне активной программы (в фоне, чтобы не тормозить анимацию).
    func startTabScan(primaryH: CGFloat) {
        guard !tabScanBusy, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != myPID else { return }
        let pid = app.processIdentifier
        let candidates = lastWins.filter { $0.pid == pid }
        guard !candidates.isEmpty else { return }
        tabScanBusy = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = AX.scanTabs(pid: pid, primaryH: primaryH)
            DispatchQueue.main.async {
                guard let self else { return }
                self.tabScanBusy = false
                guard let r = result,
                      let m = candidates.first(where: { abs($0.frame.minX - r.window.minX) < 3 &&
                                                        abs($0.frame.maxY - r.window.maxY) < 3 &&
                                                        abs($0.frame.width - r.window.width) < 3 })
                else { return }
                self.tabScans[m.id] = TabScan(windowID: m.id, rel: r.tabs.map { $0.offsetBy(dx: -r.window.minX, dy: -r.window.minY) })
                self.dirty = true
            }
        }
    }

    /// Падающий снег видно на 100% только там, где нет окон.
    func updateSnowMask(_ frames: [CGRect]) {
        guard frames != maskKey else { return }
        maskKey = frames
        let windows = CGMutablePath()
        for f in frames { windows.addRect(f) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for o in overlays {
            let outside = CGPath(rect: o.screenFrame, transform: nil).subtracting(windows, using: .winding)
            var t = CGAffineTransform(translationX: -o.screenFrame.minX, y: -o.screenFrame.minY)
            o.clearArea.path = outside.copy(using: &t)
            o.windowArea.path = windows.copy(using: &t)
        }
        CATransaction.commit()
    }

    /// Точка на пустом рабочем столе (не окно, не Док, не строка меню).
    func isEmptyDesktop(_ p: CGPoint) -> Bool {
        if windowFrames.contains(where: { $0.contains(p) }) { return false }
        if let d = dockFrame, d.insetBy(dx: -4, dy: -4).contains(p) { return false }
        if maskExtras().contains(where: { $0.contains(p) }) { return false }
        guard let scr = NSScreen.screens.first(where: { $0.frame.contains(p) }) else { return false }
        let menuBar = scr.frame.maxY - scr.visibleFrame.maxY
        return p.y < scr.frame.maxY - menuBar
    }

    // MARK: - Мышь

    func handleMouse(dt: CGFloat, now: Double) {
        let m = NSEvent.mouseLocation
        let lm = lastMouse
        lastMouse = m
        let dx = m.x - lm.x, dy = m.y - lm.y
        let mv = CGVector(dx: dx / dt, dy: dy / dt)

        do {
            let steps = max(1, Int(hypot(dx, dy) / 4))
            for id in order {
                guard let p = piles[id], isOn(p) else { continue }
                // Быстрая отбраковка по габаритам отрезка движения курсора.
                let below: CGFloat = p.kind == .window ? 18 : 3   // сосульки висят ниже кромки
                if max(m.y, lm.y) < p.top - below || min(m.y, lm.y) > p.top + 40 { continue }
                if max(m.x, lm.x) < p.frame.minX - knockRadius || min(m.x, lm.x) > p.frame.maxX + knockRadius { continue }
                for s in 0...steps {
                    let t = CGFloat(s) / CGFloat(steps)
                    let px = lm.x + dx * t, py = lm.y + dy * t
                    knock(p, px: px, py: py, mv: mv)
                    if p.kind == .window && cfg.icicles { hitIcicles(p, px: px, py: py) }
                }
            }
        }
        if cfg.cursorWind { spawnPuffs(m: m, mv: mv) }
    }

    func knock(_ p: Pile, px: CGFloat, py: CGFloat, mv: CGVector) {
        if py < p.top - 3 { return }   // курсор внутри окна (на вкладках) снег не трогает
        let i0 = max(0, Int((px - knockRadius - p.frame.minX) / colW))
        let i1 = min(p.count - 1, Int((px + knockRadius - p.frame.minX) / colW))
        guard i0 <= i1 else { return }
        for i in i0...i1 {
            let h = p.heights[i] * p.scale
            guard h > 0.4, p.visible[i] else { continue }
            let ddx = p.x(i) - px
            let cy = clamp(py, p.top, p.top + h)
            if ddx * ddx + (py - cy) * (py - cy) > knockRadius * knockRadius { continue }
            spawnChunks(p, i, mv: mv)
            p.heights[i] = 0
            dirty = true
        }
    }

    func hitIcicles(_ p: Pile, px: CGFloat, py: CGFloat) {
        guard py <= p.top + 1, py >= p.top - 16 else { return }
        for k in p.icicles.indices {
            let ic = p.icicles[k]
            guard ic.len > 1.5, ic.col < p.count, p.visible[ic.col] else { continue }
            let x = p.x(ic.col)
            if abs(px - x) <= ic.w / 2 + 3 && py >= p.top - ic.len - 2 {
                dropIcicle(p, k)
            }
        }
    }

    func dropIcicle(_ p: Pile, _ k: Int) {
        let ic = p.icicles[k]
        fallingIcicles.append(FallingIcicle(x: p.x(ic.col), y: p.top - 0.5, vy: 0, len: ic.len, w: ic.w, tilt: ic.tilt))
        p.icicles[k].len = 0
        dirty = true
    }

    func spawnPuffs(m: CGPoint, mv: CGVector) {
        let speed = hypot(mv.dx, mv.dy)
        guard speed > 450, puffs.count < 600, isEmptyDesktop(m) else { return }
        let n = min(4, Int(speed / 450))
        let vx = clamp(mv.dx, -1600, 1600), vy = clamp(mv.dy, -1600, 1600)
        for _ in 0..<n {
            puffs.append(Puff(x: m.x + rnd(-10, 10), y: m.y + rnd(-10, 10),
                              vx: vx * rnd(0.1, 0.3) + rnd(-40, 40), vy: vy * rnd(0.1, 0.3) + rnd(-20, 50),
                              r0: rnd(0.9, 2.0), age: 0, life: rnd(1.2, 2.6)))
        }
    }

    func shake(_ p: Pile, velocity v: CGVector) {
        for i in 0..<p.count where p.visible[i] && p.heights[i] > 0.4 {
            spawnChunks(p, i, mv: CGVector(dx: v.dx * 0.5, dy: v.dy * 0.5))
            p.heights[i] = 0
        }
        for k in p.icicles.indices where p.icicles[k].len > 1.5 { dropIcicle(p, k) }
        dirty = true
    }

    func shakeAll() {
        for id in order {
            guard let p = piles[id], p.kind != .bottom else { continue }
            shake(p, velocity: CGVector(dx: rnd(-300, 300), dy: rnd(0, 400)))
        }
    }

    func spawnChunks(_ p: Pile, _ i: Int, mv: CGVector) {
        let h = p.heights[i] * p.scale
        let n = max(1, Int(h / 4))
        let mx = clamp(mv.dx, -1800, 1800), my = clamp(mv.dy, -1800, 1800)
        for _ in 0..<n where chunks.count < maxChunks {
            chunks.append(Chunk(
                x: p.x(i) + rnd(-1.5, 1.5),
                y: p.top + rnd(0, h),
                vx: mx * rnd(0.15, 0.5) + rnd(-50, 50),
                vy: max(0, my) * rnd(0.1, 0.4) + rnd(60, 260),
                r: rnd(1.0, 2.6),
                src: p.id, age: 0))
        }
    }

    // MARK: - Физика

    func grow(_ dt: CGFloat) {
        guard cfg.snowing else { return }
        let gs = max(5, cfg.growSeconds)
        for id in order {
            guard let p = piles[id] else { continue }
            let speed = p.kind == .bottom ? gs * 3 : gs
            for i in 0..<p.count where p.heights[i] < p.targets[i] {
                p.heights[i] = min(p.targets[i], p.heights[i] + p.targets[i] * dt / speed)
                dirty = true
            }
            if p.kind == .bottom { settle(p) }
            if cfg.icicles && p.kind == .window {
                for k in p.icicles.indices where p.icicles[k].len < p.icicles[k].maxLen {
                    let c = p.icicles[k].col
                    guard c < p.count, p.heights[c] > 3 else { continue }
                    p.icicles[k].len = min(p.icicles[k].maxLen, p.icicles[k].len + p.icicles[k].maxLen * dt / (speed * 1.5))
                    dirty = true
                }
            }
        }
    }

    /// Снег внизу понемногу оплывает: выкопанные курсором ямки и крутые края сглаживаются.
    func settle(_ p: Pile) {
        let n = p.count
        guard n > 2 else { return }
        let h = p.heights
        var changed = false
        for i in 1..<(n - 1) where p.visible[i] {
            let lap = h[i - 1] + h[i + 1] - 2 * h[i]
            if abs(lap) > 0.4 {
                p.heights[i] = max(0, h[i] + lap * 0.12)
                changed = true
            }
        }
        if changed { dirty = true }
    }

    /// Каждая галочка отвечает только за своё: Док, вкладки и окна включаются независимо.
    /// (Док, вкладки и низ экрана и так попадают в order, только когда включены.)
    func isOn(_ p: Pile) -> Bool { p.kind != .window || cfg.piles }

    /// Пересёк ли падающий предмет поверхность какого-нибудь сугроба.
    func surfaceHit(x: CGFloat, from oy: CGFloat, to ny: CGFloat, exclude: Int? = nil) -> (Pile, Int)? {
        for id in order where id != exclude {
            guard let p = piles[id], isOn(p), x >= p.frame.minX, x < p.frame.maxX,
                  let i = p.col(at: x), p.visible[i] else { continue }
            if p.kind != .bottom && p.targets[i] <= 0 { continue }
            let s = p.surface(i)
            if oy >= s && ny < s { return (p, i) }
        }
        return nil
    }

    func deposit(_ p: Pile, _ i: Int, _ add: CGFloat) {
        for j in max(0, i - 1)...min(p.count - 1, i + 1) {
            let cap = p.kind == .bottom ? p.targets[j] * 2 + 4 : p.targets[j] * 1.6 + 2
            p.heights[j] = min(cap, p.heights[j] + add)
        }
        dirty = true
    }

    func updateParticles(dt: CGFloat) {
        if !chunks.isEmpty {
            let drag = pow(0.5, dt)
            var alive: [Chunk] = []
            alive.reserveCapacity(chunks.count)
            for var c in chunks {
                let oy = c.y
                c.vy += gravity * dt
                c.vx *= drag
                c.x += c.vx * dt
                c.y += c.vy * dt
                c.age += dt
                if c.y < minY - 40 || c.age > 10 { continue }
                // Комок может приземлиться на сугроб ниже.
                if c.vy < 0, let (p, i) = surfaceHit(x: c.x, from: oy, to: c.y, exclude: c.src) {
                    deposit(p, i, c.r * c.r * 0.35)
                    continue
                }
                alive.append(c)
            }
            chunks = alive
        }

        if !fallingIcicles.isEmpty {
            var keep: [FallingIcicle] = []
            for var f in fallingIcicles {
                let oy = f.y - f.len
                f.vy += gravity * dt
                f.y += f.vy * dt
                if f.y < minY - 60 { continue }
                if let (p, i) = surfaceHit(x: f.x, from: oy, to: f.y - f.len) {
                    // Разбилась: осколки и звон.
                    let sy = p.surface(i)
                    for _ in 0..<6 where chunks.count < maxChunks {
                        chunks.append(Chunk(x: f.x + rnd(-2, 2), y: sy + 1, vx: rnd(-90, 90), vy: rnd(80, 220),
                                            r: rnd(0.7, 1.4), src: p.id, age: 0))
                    }
                    Sound.play("Tink", volume: 0.3)
                    continue
                }
                keep.append(f)
            }
            fallingIcicles = keep
        }

        if !puffs.isEmpty {
            let drag = pow(0.25, dt)
            puffs = puffs.compactMap { p in
                var p = p
                p.vy -= 50 * dt
                p.vx *= drag
                p.vy *= drag
                p.x += p.vx * dt
                p.y += p.vy * dt
                p.age += dt
                return p.age < p.life ? p : nil
            }
        }
    }

    // MARK: - Отрисовка

    func render() {
        let pilePath = CGMutablePath()
        let iciPath = CGMutablePath()
        let shinePath = CGMutablePath()
        do {
            for id in order {
                guard let p = piles[id], isOn(p) else { continue }
                addPile(p, to: pilePath)
                if cfg.icicles && p.kind == .window { addIcicles(p, to: iciPath, shine: shinePath) }
            }
        }
        for f in fallingIcicles { addIcicleShape(x: f.x, top: f.y, len: f.len, w: f.w, tilt: f.tilt, to: iciPath, shine: shinePath) }

        let chunkPath = CGMutablePath()
        for c in chunks {
            chunkPath.addEllipse(in: CGRect(x: c.x - c.r, y: c.y - c.r, width: c.r * 2, height: c.r * 2))
        }
        let puffPath = CGMutablePath()
        for p in puffs where p.r > 0.1 {
            puffPath.addEllipse(in: CGRect(x: p.x - p.r, y: p.y - p.r, width: p.r * 2, height: p.r * 2))
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for o in overlays {
            var t = CGAffineTransform(translationX: -o.screenFrame.minX, y: -o.screenFrame.minY)
            let pp = pilePath.copy(using: &t)
            o.pileLayer.path = pp
            o.pileLayer.shadowPath = pp
            o.icicleLayer.path = iciPath.copy(using: &t)
            o.chunkLayer.path = chunkPath.copy(using: &t)
            o.puffLayer.path = puffPath.copy(using: &t)
            o.icicleShine.path = shinePath.copy(using: &t)
        }
        CATransaction.commit()
        dirty = false
        particlesOnScreen = hasParticles
    }

    func addPile(_ p: Pile, to path: CGMutablePath) {
        let n = p.count
        let base = p.top - 1
        func on(_ i: Int) -> Bool { p.visible[i] && p.heights[i] * p.scale > 0.3 }
        var i = 0
        while i < n {
            while i < n && !on(i) { i += 1 }
            if i >= n { break }
            let start = i
            while i < n && on(i) { i += 1 }
            let end = i - 1
            if p.kind == .bottom {
                addBottomRun(p, start, end, to: path)
                continue
            }
            path.move(to: CGPoint(x: p.x(start) - colW / 2, y: base))
            for j in start...end {
                // лёгкое сглаживание соседних колонок
                let h = p.scale * (p.heights[max(start, j - 1)] + 2 * p.heights[j] + p.heights[min(end, j + 1)]) / 4
                path.addLine(to: CGPoint(x: p.x(j), y: p.top + h))
            }
            path.addLine(to: CGPoint(x: p.x(end) + colW / 2, y: base))
            path.closeSubpath()
        }
    }

    /// Сугроб внизу экрана: сильнее сглажен и плавно сходит на нет у Дока и окон (не обрывается ступенькой).
    func addBottomRun(_ p: Pile, _ start: Int, _ end: Int, to path: CGMutablePath) {
        let n = p.count
        let fade: CGFloat = 36          // ширина «спуска» у края, px
        path.move(to: CGPoint(x: p.x(start) - colW / 2, y: p.top - 1))
        var j = start
        while j <= end {
            var sum: CGFloat = 0, wsum: CGFloat = 0
            for d in -3...3 {
                let k = min(end, max(start, j + d))
                let w: CGFloat = 4 - CGFloat(abs(d))
                sum += p.heights[k] * w
                wsum += w
            }
            var h = sum / wsum
            // у края экрана снег упирается в рамку, у Дока/окна — сходит на нет
            let dl = start == 0 ? .infinity : CGFloat(j - start) * colW + colW / 2
            let dr = end == n - 1 ? .infinity : CGFloat(end - j) * colW + colW / 2
            let d = min(dl, dr)
            if d < fade { h *= sqrt(d / fade) }
            path.addLine(to: CGPoint(x: p.x(j), y: p.top + h * p.scale))
            j += j == end ? 1 : min(2, end - j)   // через колонку — путь вдвое короче
        }
        path.addLine(to: CGPoint(x: p.x(end) + colW / 2, y: p.top - 1))
        path.closeSubpath()
    }

    func addIcicles(_ p: Pile, to path: CGMutablePath, shine: CGMutablePath) {
        for ic in p.icicles where ic.len > 1.5 && ic.col < p.count && p.visible[ic.col] {
            // растущая сосулька сначала толстеет у основания, потом вытягивается
            let grow = ic.len / ic.maxLen
            addIcicleShape(x: p.x(ic.col), top: p.top + 0.5, len: ic.len, w: ic.w * (0.6 + 0.4 * grow),
                           tilt: ic.tilt * grow, to: path, shine: shine)
        }
    }

    /// Сосулька: широкое основание, вогнутые бока и длинный тонкий кончик с лёгким наклоном.
    func addIcicleShape(x: CGFloat, top: CGFloat, len: CGFloat, w: CGFloat, tilt: CGFloat,
                        to path: CGMutablePath, shine: CGMutablePath) {
        let tip = CGPoint(x: x + tilt, y: top - len)
        path.move(to: CGPoint(x: x - w / 2, y: top))
        path.addCurve(to: tip,
                      control1: CGPoint(x: x - w * 0.5, y: top - len * 0.2),
                      control2: CGPoint(x: x - w * 0.07 + tilt * 0.5, y: top - len * 0.55))
        path.addCurve(to: CGPoint(x: x + w / 2, y: top),
                      control1: CGPoint(x: x + w * 0.07 + tilt * 0.5, y: top - len * 0.55),
                      control2: CGPoint(x: x + w * 0.5, y: top - len * 0.2))
        path.closeSubpath()
        // блик вдоль левого бока
        if len > 4 {
            shine.move(to: CGPoint(x: x - w * 0.2, y: top - 1))
            shine.addQuadCurve(to: CGPoint(x: x - w * 0.04 + tilt * 0.45, y: top - len * 0.6),
                               control: CGPoint(x: x - w * 0.22, y: top - len * 0.3))
        }
    }
}

// MARK: - Запомненное положение Дока

/// Файл в ~/Library/Application Support/NewYearSnow — переживает обновления приложения,
/// поэтому сугроб на Доке есть сразу, даже пока «Универсальный доступ» ещё не выдан заново.
enum DockCache {
    static var memo: CGRect??
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NewYearSnow/dock.plist")
    }

    static func save(_ f: CGRect) {
        if let m = memo, let old = m, abs(old.minX - f.minX) < 0.5, abs(old.width - f.width) < 0.5,
           abs(old.minY - f.minY) < 0.5, abs(old.height - f.height) < 0.5 { return }
        memo = .some(f)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        (([f.minX, f.minY, f.width, f.height].map { Double($0) }) as NSArray).write(to: url, atomically: true)
    }

    static func load() -> CGRect? {
        if let m = memo { return valid(m) }
        let a = NSArray(contentsOf: url) as? [Double]
        let f = a.flatMap { $0.count == 4 ? CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) : nil }
        memo = .some(f)
        return valid(f)
    }

    /// Док действительно виден внизу экрана (не скрыт автоматически и не сбоку).
    static func valid(_ f: CGRect?) -> CGRect? {
        guard let f, let s = NSScreen.screens.first, s.visibleFrame.minY - s.frame.minY > 10 else { return nil }
        return f
    }
}

// MARK: - Accessibility: Док и вкладки

enum AX {
    static func value(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }
    static func role(_ el: AXUIElement) -> String? { value(el, kAXRoleAttribute) as? String }
    static func children(_ el: AXUIElement) -> [AXUIElement] { value(el, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = value(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }
    /// Рамка элемента в координатах Cocoa.
    static func frame(_ el: AXUIElement, primaryH: CGFloat) -> CGRect? {
        guard let pos = value(el, kAXPositionAttribute), let size = value(el, kAXSizeAttribute),
              CFGetTypeID(pos) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pos as! AXValue, .cgPoint, &p)
        AXValueGetValue(size as! AXValue, .cgSize, &s)
        return CGRect(x: p.x, y: primaryH - p.y - s.height, width: s.width, height: s.height)
    }

    /// Вкладки (AXTabGroup → AXRadioButton/AXTab) в активном окне программы.
    static func scanTabs(pid: pid_t, primaryH: CGFloat) -> (window: CGRect, tabs: [CGRect])? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let win = element(app, kAXFocusedWindowAttribute), let wf = frame(win, primaryH: primaryH) else { return nil }
        var tabs: [CGRect] = []
        var queue: [(AXUIElement, Int)] = [(win, 0)]
        var visited = 0
        let skip: Set<String> = ["AXWebArea", kAXScrollAreaRole, kAXTableRole, kAXOutlineRole, kAXListRole, kAXTextAreaRole]
        while !queue.isEmpty && visited < 500 {
            let (el, depth) = queue.removeFirst()
            visited += 1
            let r = role(el) ?? ""
            if r == kAXTabGroupRole {
                for c in children(el) {
                    let cr = role(c) ?? ""
                    if cr == kAXRadioButtonRole || cr == "AXTab", let f = frame(c, primaryH: primaryH), f.width > 20, f.height > 10 {
                        tabs.append(f)
                    }
                }
                continue
            }
            if depth >= 7 || skip.contains(r) { continue }
            for c in children(el) { queue.append((c, depth + 1)) }
        }
        // Нужны только полоски вкладок у верхнего края окна.
        tabs = tabs.filter { $0.maxY >= wf.maxY - 120 && $0.maxY <= wf.maxY + 1 }
        return tabs.isEmpty ? nil : (wf, tabs)
    }
}
