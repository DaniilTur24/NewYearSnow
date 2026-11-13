// Модели: сугроб, сосулька, комки снега.

import Cocoa

enum PileKind { case window, dock, bottom, tab }

struct Icicle {
    var col: Int            // колонка сугроба, под которой висит
    var len: CGFloat        // текущая длина
    var maxLen: CGFloat
    var w: CGFloat          // ширина у основания
    var tilt: CGFloat       // насколько кончик отклонён вбок
}

/// Сугроб на верхней кромке чего-либо: окна, Дока, вкладки или низа экрана.
final class Pile {
    let id: Int
    let kind: PileKind
    var frame: CGRect            // рамка в глобальных координатах Cocoa (y вверх); снег лежит на frame.maxY
    var heights: [CGFloat] = []  // текущая высота снега в каждой колонке
    var targets: [CGFloat] = []  // «естественная» высота, к которой снег нарастает
    var visible: [Bool] = []     // колонка не перекрыта другим окном
    var icicles: [Icicle] = []
    var lastSeen: Double = 0
    var scale: CGFloat = 1       // < 1 для окон, упёртых в строку меню
    let seed: CGFloat
    let base, inset, taper, amp: CGFloat

    init(id: Int, kind: PileKind, frame: CGRect, fill: CGFloat) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.seed = CGFloat(abs(id) % 997) * 0.731 + 0.4
        switch kind {
        case .window: (base, inset, taper, amp) = (9, 8, 26, 1)
        case .dock:   (base, inset, taper, amp) = (11, 14, 34, 1)
        case .tab:    (base, inset, taper, amp) = (3.5, 5, 8, 0.35)
        case .bottom: (base, inset, taper, amp) = (16, 0, 0, 1.4)
        }
        rebuild(keep: false, fill: fill)
    }

    var top: CGFloat { frame.maxY }
    var count: Int { heights.count }
    func x(_ i: Int) -> CGFloat { frame.minX + (CGFloat(i) + 0.5) * colW }
    func col(at x: CGFloat) -> Int? {
        let i = Int(floor((x - frame.minX) / colW))
        return i >= 0 && i < count ? i : nil
    }
    func surface(_ i: Int) -> CGFloat { top + heights[i] * scale }

    /// Неровный профиль сугроба: сумма синусов + сужение к скруглённым углам.
    func target(local lx: CGFloat, width w: CGFloat) -> CGFloat {
        if kind == .bottom {
            // Пологие длинные волны + сугробы, наметённые в углы экрана, + мелкая рябь.
            var t = 11 + 5 * sin(lx * 0.0045 + seed)
                       + 3 * sin(lx * 0.012 + seed * 1.7)
                       + 1.3 * sin(lx * 0.031 + seed * 2.9)
                       + 0.45 * sin(lx * 0.093 + seed * 4.3)
            t += 15 * exp(-lx / 150) + 15 * exp(-(w - lx) / 150)
            return max(2, t) * WinterMode.current.pileScale
        }
        var t = base + amp * (3.5 * sin(lx * 0.023 + seed)
                            + 2.2 * sin(lx * 0.061 + seed * 2.1)
                            + 1.2 * sin(lx * 0.17 + seed * 3.7))
        t *= WinterMode.current.pileScale
        let d = min(lx, w - lx) - inset
        if d <= 0 { return 0 }
        if d < taper { t *= sqrt(d / taper) }
        return max(0, t)
    }

    func retarget() {
        targets = (0..<count).map { target(local: (CGFloat($0) + 0.5) * colW, width: frame.width) }
    }

    func rebuild(keep: Bool, fill: CGFloat) {
        let n = max(1, Int(frame.width / colW))
        let old = heights
        heights = Array(repeating: 0, count: n)
        retarget()
        if keep && !old.isEmpty {
            heights = (0..<n).map { i in
                let j = min(old.count - 1, i * old.count / n)
                return min(old[j], targets[i] * 1.6)
            }
        } else {
            heights = targets.map { $0 * fill }
        }
        visible = Array(repeating: true, count: n)
        makeIcicles(fill: keep ? 0 : fill)
    }

    func makeIcicles(fill: CGFloat) {
        icicles = []
        guard kind == .window else { return }
        // Как в природе: в основном короткие, изредка длинные; иногда рядом с большой — маленькая.
        func add(_ x: CGFloat, maxLen m: CGFloat) {
            let c = Int(x / colW)
            guard c >= 0, c < count else { return }
            icicles.append(Icicle(col: c, len: m * fill, maxLen: m,
                                  w: 2 + m * 0.13 + rnd(0, 0.8), tilt: rnd(-0.08, 0.08) * m))
        }
        let mode = WinterMode.current
        var x = rnd(30, 80) / mode.icicleCount
        while x < frame.width - 24 {
            let u = rnd(0, 1)
            let m = (4 + u * u * 18) * mode.icicleLength   // 4…22 px, чаще короткие
            add(x, maxLen: m)
            if m > 9 && Bool.random() {      // маленькая соседка
                add(x + (Bool.random() ? 1 : -1) * rnd(4, 7), maxLen: m * rnd(0.3, 0.55))
            }
            x += rnd(45, 125) / mode.icicleCount
        }
    }
}

struct Chunk {
    var x, y, vx, vy, r: CGFloat
    var src: Int
    var age: CGFloat
}

/// Снежная пыль, которую курсор поднимает над пустым столом.
struct Puff {
    var x, y, vx, vy, r0: CGFloat
    var age, life: CGFloat
    var r: CGFloat { r0 * max(0, 1 - age / life) }
}

struct FallingIcicle {
    var x, y, vy, len, w, tilt: CGFloat
}
