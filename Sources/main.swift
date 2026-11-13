// NewYearSnow — праздничное оформление macOS.
// Здесь: меню ❄️ в строке меню, таймер до Нового года, автовыключение и запуск.

import Cocoa

// MARK: - Пункты меню

/// Пункт меню с замыканием вместо селектора.
final class ActionItem: NSMenuItem {
    var handler: () -> Void = {}
    convenience init(_ title: String, checked: Bool? = nil, key: String = "", _ handler: @escaping () -> Void) {
        self.init(title: title, action: #selector(fire), keyEquivalent: key)
        self.target = self
        self.handler = handler
        if let checked { state = checked ? .on : .off }
    }
    @objc func fire() { handler() }
}

func info(_ title: String) -> NSMenuItem {
    let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    i.isEnabled = false
    return i
}

// MARK: - Приложение

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let snow = SnowController()
    lazy var fireworks = Fireworks(snow: snow)
    lazy var santa = Santa(snow: snow, fireworks: fireworks)
    var music: Music?            // аудио создаётся, только когда музыку включили
    var statusItem: NSStatusItem!
    let menu = NSMenu()
    var clock: Timer?
    var lastClock = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        snow.onTick = { [weak self] now, dt in self?.santa.tick(now: now, dt: dt) }
        snow.enabled = !S.autoOff || inSeason()
        snow.start()
        fireworks.start()
        if S.music && snow.enabled { setMusic(true) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "❄️"
        menu.delegate = self
        menu.autoenablesItems = false   // чтобы строки состояния оставались серыми
        statusItem.menu = menu
        rebuildMenu()

        let c = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.clockTick() }
        }
        RunLoop.main.add(c, forMode: .common)
        clock = c
        clockTick()

        // Один раз попросим доступ, нужный для сугроба на Доке и снега на вкладках.
        let asked = "askedAccessibility"
        if !AXIsProcessTrusted() && !UserDefaults.standard.bool(forKey: asked) {
            UserDefaults.standard.set(true, forKey: asked)
            askAccessibility()
        }
    }

    // MARK: Часы: таймер, полночь, сезон

    func clockTick() {
        let now = Date()
        // Ровно в полночь 1 января — салют и поздравление.
        let ny = nextNewYear(after: lastClock)
        if lastClock < ny && now >= ny && snow.enabled { fireworks.grandShow() }
        lastClock = now

        // Сезон: после 15 января украшения выключаются сами.
        let on = !S.autoOff || inSeason(now)
        if on != snow.enabled {
            snow.setEnabled(on)
            setMusic(on && S.music)   // после праздников музыка тоже замолкает
        }
        statusItem.button?.title = (S.countdown && on) ? "❄️ " + countdownShort(now) : "❄️"
    }

    func countdownShort(_ now: Date) -> String {
        if isNewYearHolidays(now) { return "🎆" }
        let s = Int(nextNewYear(after: now).timeIntervalSince(now))
        let d = s / 86400
        if d >= 1 { return "\(d) д" }
        return String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }

    // MARK: Меню

    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu() }

    func rebuildMenu() {
        let m = menu
        m.removeAllItems()
        m.addItem(info("Режим зимы"))
        for (k, mode) in WinterMode.all.enumerated() {
            m.addItem(ActionItem(mode.title, checked: S.mode == k) { [unowned self] in
                let old = WinterMode.current
                S.mode = k
                snow.applyMode(from: old)
            })
        }
        m.addItem(.separator())
        m.addItem(ActionItem("Сугробы на окнах", checked: S.piles) { [unowned self] in S.piles.toggle(); snow.dirty = true })
        m.addItem(.separator())
        m.addItem(ActionItem("Позвать Санту 🎅") { [unowned self] in santa.call() })
        m.addItem(ActionItem("Запустить салют 🎆") { [unowned self] in
            guard let f = NSScreen.main?.frame else { return }
            for k in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(k) * 0.4) {
                    self.fireworks.launch(to: CGPoint(x: f.minX + rnd(f.width * 0.2, f.width * 0.8), y: f.minY + rnd(f.height * 0.5, f.height * 0.8)))
                }
            }
        })
        m.addItem(.separator())
        m.addItem(ActionItem("Музыка 🎵", checked: S.music) { [unowned self] in
            S.music.toggle()
            setMusic(S.music && snow.enabled)
        })
        if let title = music?.currentTitle {
            m.addItem(info("♪ \(title)"))
            m.addItem(ActionItem("Следующая мелодия ⏭") { [unowned self] in music?.next() })
        }
        m.addItem(.separator())
        // Без «Универсального доступа» не работают Док и вкладки — пункт виден, только пока доступа нет.
        if !AXIsProcessTrusted() {
            m.addItem(ActionItem("Разрешить снег на Доке и вкладках…") { [unowned self] in askAccessibility() })
        }
        m.addItem(ActionItem("Выход", key: "q") { NSApp.terminate(nil) })
    }

    func setMusic(_ on: Bool) {
        if on && music == nil { music = Music() }
        music?.setOn(on)
    }

    func askAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}

// MARK: - Запуск

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // без иконки в Dock
let delegate = AppDelegate()
app.delegate = delegate
app.run()
