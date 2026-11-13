// Рождественская музыка в стиле музыкальной шкатулки.
// Звук синтезируется прямо здесь из нот — никаких аудиофайлов.
// Все мелодии старинные и общественное достояние.

import AVFoundation

struct Tune {
    let title: String
    let beat: Double        // длительность одной доли (четверти), секунд
    let notes: String       // "G4:1.5 A4:.5 R:1 …" — нота:доли, R — пауза
}

final class Music {
    static let tunes: [Tune] = [
        Tune(title: "Jingle Bells", beat: 0.42, notes: """
            D4:1 B4:1 A4:1 G4:1 D4:3 D4:.5 D4:.5
            D4:1 B4:1 A4:1 G4:1 E4:4
            E4:1 C5:1 B4:1 A4:1 F#4:4
            D5:1 D5:1 C5:1 A4:1 B4:4
            D4:1 B4:1 A4:1 G4:1 D4:4
            D4:1 B4:1 A4:1 G4:1 E4:3 E4:1
            E4:1 C5:1 B4:1 A4:1 D5:1 D5:1 D5:1 D5:1
            E5:1 D5:1 C5:1 A4:1 G4:2 D5:2
            B4:1 B4:1 B4:2 B4:1 B4:1 B4:2 B4:1 D5:1 G4:1.5 A4:.5 B4:4
            C5:1 C5:1 C5:1.5 C5:.5 C5:1 B4:1 B4:1 B4:.5 B4:.5 B4:1 A4:1 A4:1 B4:1 A4:2 D5:2
            B4:1 B4:1 B4:2 B4:1 B4:1 B4:2 B4:1 D5:1 G4:1.5 A4:.5 B4:4
            C5:1 C5:1 C5:1 C5:1 C5:1 B4:1 B4:1 B4:.5 B4:.5 D5:1 D5:1 C5:1 A4:1 G4:4
            """),
        Tune(title: "We Wish You a Merry Christmas", beat: 0.38, notes: """
            D4:1
            G4:1 G4:.5 A4:.5 G4:.5 F#4:.5 E4:1 E4:1 E4:1
            A4:1 A4:.5 B4:.5 A4:.5 G4:.5 F#4:1 D4:1 D4:1
            B4:1 B4:.5 C5:.5 B4:.5 A4:.5 G4:1 E4:1 D4:.5 D4:.5
            E4:1 A4:1 F#4:1 G4:2 D4:1
            G4:1 G4:.5 A4:.5 G4:.5 F#4:.5 E4:1 E4:1 E4:1
            A4:1 A4:.5 B4:.5 A4:.5 G4:.5 F#4:1 D4:1 D4:1
            B4:1 B4:.5 C5:.5 B4:.5 A4:.5 G4:1 E4:1 D4:.5 D4:.5
            E4:1 A4:1 F#4:1 G4:3
            """),
        Tune(title: "Silent Night", beat: 0.5, notes: """
            G4:1.5 A4:.5 G4:1 E4:3
            G4:1.5 A4:.5 G4:1 E4:3
            D5:2 D5:1 B4:3
            C5:2 C5:1 G4:3
            A4:2 A4:1 C5:1.5 B4:.5 A4:1 G4:1.5 A4:.5 G4:1 E4:3
            A4:2 A4:1 C5:1.5 B4:.5 A4:1 G4:1.5 A4:.5 G4:1 E4:3
            D5:2 D5:1 F5:1.5 D5:.5 B4:1 C5:3 E5:3
            C5:1.5 G4:.5 E4:1 G4:1.5 F4:.5 D4:1 C4:6
            """),
        Tune(title: "Deck the Halls", beat: 0.36, notes: """
            G4:1.5 F4:.5 E4:1 D4:1 C4:1 D4:1 E4:1 C4:1
            D4:.5 E4:.5 F4:.5 D4:.5 E4:1.5 D4:.5 C4:1 B3:1 C4:2
            G4:1.5 F4:.5 E4:1 D4:1 C4:1 D4:1 E4:1 C4:1
            D4:.5 E4:.5 F4:.5 D4:.5 E4:1.5 D4:.5 C4:1 B3:1 C4:2
            D4:1.5 E4:.5 F4:1 D4:1 E4:1.5 F4:.5 G4:1 D4:1
            E4:.5 F#4:.5 G4:1 A4:.5 B4:.5 C5:1 B4:1 A4:1 G4:2
            G4:1.5 F4:.5 E4:1 D4:1 C4:1 D4:1 E4:1 C4:1
            A4:.5 A4:.5 A4:.5 A4:.5 G4:1.5 F4:.5 E4:1 D4:1 C4:2
            """),
        Tune(title: "Carol of the Bells", beat: 0.34, notes: """
            Bb4:1 A4:.5 Bb4:.5 G4:1 Bb4:1 A4:.5 Bb4:.5 G4:1 Bb4:1 A4:.5 Bb4:.5 G4:1 Bb4:1 A4:.5 Bb4:.5 G4:1
            Bb4:1 A4:.5 Bb4:.5 G4:1 Bb4:1 A4:.5 Bb4:.5 G4:1 Bb4:1 A4:.5 Bb4:.5 G4:1 Bb4:1 A4:.5 Bb4:.5 G4:1
            D5:1 C5:.5 D5:.5 Bb4:1 D5:1 C5:.5 D5:.5 Bb4:1 D5:1 C5:.5 D5:.5 Bb4:1 D5:1 C5:.5 D5:.5 Bb4:1
            Bb4:1 A4:.5 Bb4:.5 G4:1 Bb4:1 A4:.5 Bb4:.5 G4:1 Bb4:1 A4:.5 Bb4:.5 G4:1 G4:3
            """),
    ]

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let reverb = AVAudioUnitReverb()
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!   // эхо (reverb) работает только со стерео
    var cache: [Int: AVAudioPCMBuffer] = [:]
    var index = Int.random(in: 0..<Music.tunes.count)
    var playing = false
    var generation = 0              // защищает от «старых» колбэков после «Следующая» / «Стоп»

    var currentTitle: String? { playing ? Music.tunes[index].title : nil }

    init() {
        engine.attach(player)
        engine.attach(reverb)
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = 28
        engine.connect(player, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        player.volume = 0.35
    }

    func setOn(_ on: Bool) { on ? start() : stop() }

    func start() {
        guard !playing else { return }
        do { try engine.start() } catch { return }
        playing = true
        player.play()
        scheduleCurrent()
    }

    func stop() {
        guard playing else { return }
        playing = false
        generation += 1
        player.stop()
        engine.stop()
    }

    func next() {
        guard playing else { return }
        generation += 1
        player.stop()
        index = (index + 1) % Music.tunes.count
        player.play()
        scheduleCurrent()
    }

    func scheduleCurrent() {
        let gen = generation
        buffer(index) { [weak self] buf in
            guard let self, self.playing, gen == self.generation else { return }
            self.player.scheduleBuffer(buf, completionCallbackType: .dataPlayedBack) { _ in
                DispatchQueue.main.async {
                    guard self.playing, gen == self.generation else { return }
                    self.index = (self.index + 1) % Music.tunes.count
                    self.scheduleCurrent()
                }
            }
        }
    }

    /// Мелодия синтезируется один раз, в фоне, и потом берётся из кеша.
    func buffer(_ i: Int, _ done: @escaping (AVAudioPCMBuffer) -> Void) {
        if let b = cache[i] { done(b); return }
        let tune = Music.tunes[i], fmt = format
        DispatchQueue.global(qos: .utility).async {
            let b = Music.render(tune, format: fmt)
            DispatchQueue.main.async {
                self.cache[i] = b
                done(b)
            }
        }
    }

    // MARK: - Синтез

    /// «G4», «F#4», «Bb3» → номер MIDI-ноты. «R» — пауза (nil).
    static func midi(_ name: Substring) -> Int? {
        guard let letter = name.first, letter != "R" else { return nil }
        let base: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        var semis = base[letter] ?? 0
        var rest = name.dropFirst()
        if rest.first == "#" { semis += 1; rest = rest.dropFirst() }
        if rest.first == "b" { semis -= 1; rest = rest.dropFirst() }
        let octave = Int(rest) ?? 4
        return 12 * (octave + 1) + semis
    }

    static func parse(_ s: String) -> [(Int?, Double)] {
        s.split(whereSeparator: { $0 == " " || $0 == "\n" }).compactMap { tok in
            let parts = tok.split(separator: ":")
            guard parts.count == 2, let beats = Double(parts[1]) else { return nil }
            return (midi(parts[0]), beats)
        }
    }

    /// Музыкальная шкатулка: каждая нота — затухающий «звон» из нескольких обертонов.
    static func render(_ t: Tune, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let notes = parse(t.notes)
        let total = notes.reduce(0) { $0 + $1.1 } * t.beat + 3.5      // + хвост и пауза перед следующей
        let n = Int(total * sr)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        let out = buf.floatChannelData![0]
        for s in 0..<n { out[s] = 0 }

        // (кратность частоты, громкость, скорость затухания)
        let partials: [(Double, Double, Double)] = [(1, 1, 2.2), (2, 0.32, 4), (3, 0.1, 6), (4.16, 0.07, 9), (5.43, 0.035, 12)]
        var time = 0.0
        for (m, beats) in notes {
            defer { time += beats * t.beat }
            guard let m else { continue }
            let f = 440 * pow(2, Double(m + 12 - 69) / 12)     // на октаву выше — как у шкатулки
            let start = Int(time * sr)
            let len = min(n - start, Int(2.6 * sr))
            guard len > 0 else { continue }
            for (mult, amp, decay) in partials {
                let w = 2 * Double.pi * f * mult / sr
                for s in 0..<len {
                    let tt = Double(s) / sr
                    let env = exp(-tt * decay) * min(1, tt / 0.003)
                    out[start + s] += Float(amp * env * sin(w * Double(s)))
                }
            }
        }
        var peak: Float = 0
        for s in 0..<n { peak = max(peak, abs(out[s])) }
        if peak > 0 {
            let g = 0.7 / peak
            for s in 0..<n { out[s] *= g }
        }
        // Остальные каналы (стерео) — копия первого.
        for c in 1..<Int(format.channelCount) {
            let ch = buf.floatChannelData![c]
            for s in 0..<n { ch[s] = out[s] }
        }
        return buf
    }
}
