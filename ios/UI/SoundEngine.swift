import AVFoundation
import GameCore

/// The game's voice, ported note-for-note from the web Sound module: one
/// flexible tone with optional pitch glide + gentle vibrato, warm sine/triangle
/// timbres, quick attacks, soft tails. Every cue keeps its exact web recipe
/// (frequencies, durations, offsets, gains).
///
/// Implementation: each cue renders ONCE into a PCM buffer (sample-accurate
/// synthesis of the web's oscillator + exponential envelope graph) and plays
/// through a small AVAudioPlayerNode pool. Zero per-frame work, zero live DSP.
public final class Sound {

    public static let shared = Sound()

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var started = false

    public var enabled: Bool {
        get { UserDefaults.standard.string(forKey: "ninelives.pref.sound") != "0" }
        set {
            UserDefaults.standard.set(newValue ? "1" : "0", forKey: "ninelives.pref.sound")
            if newValue { play("on", [Voice(freq: 660, dur: 0.09, gain: 0.05, glideTo: 880)]) }
        }
    }

    private init() {}

    private func startIfNeeded() {
        guard !started else { return }
        started = true
        do {
            // Ambient: mixes with the player's own music, honors the mute switch.
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            for _ in 0..<6 {
                let p = AVAudioPlayerNode()
                engine.attach(p)
                engine.connect(p, to: engine.mainMixerNode, format: format)
                players.append(p)
            }
            try engine.start()
        } catch {
            players.removeAll()
        }
    }

    // MARK: - The voice (the web `voice()` verbatim)

    struct Voice {
        var freq: Double
        var dur: Double = 0.12
        var type: Wave = .sine
        var gain: Double = 0.05
        var at: Double = 0
        var glideTo: Double? = nil
        var glideFrac: Double = 0.85
        var attack: Double = 0.01
        var vibrato: Double = 0
        var vibratoDepth: Double = 8
    }

    enum Wave { case sine, triangle, sawtooth }

    /// Render a set of voices into one mixed buffer.
    private func render(_ voices: [Voice]) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        let total = voices.map { $0.at + $0.dur + 0.05 }.max() ?? 0.1
        let frames = AVAudioFrameCount(total * sr)
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buf.frameLength = frames
        let out = buf.floatChannelData![0]
        for i in 0..<Int(frames) { out[i] = 0 }

        for v in voices {
            let start = Int(v.at * sr)
            let n = Int(v.dur * sr)
            guard n > 0 else { continue }
            var phase = 0.0
            let f0 = v.freq
            let f1 = v.glideTo ?? v.freq
            let glideEnd = v.dur * v.glideFrac
            for i in 0..<n {
                let t = Double(i) / sr
                // Exponential frequency glide (the web's exponentialRamp).
                var f: Double
                if f1 != f0, glideEnd > 0 {
                    let gt = min(1, t / glideEnd)
                    f = f0 * pow(f1 / f0, gt)
                } else {
                    f = f0
                }
                if v.vibrato > 0 {
                    f += sin(2 * .pi * v.vibrato * t) * v.vibratoDepth
                }
                phase += 2 * .pi * f / sr
                let s: Double
                switch v.type {
                case .sine: s = sin(phase)
                case .triangle: s = (2 / Double.pi) * asin(sin(phase))
                case .sawtooth:
                    let cyc = phase / (2 * .pi)
                    s = 2 * (cyc - (cyc + 0.5).rounded(.down)) // -1..1 saw
                }
                // Exponential envelope: 0.0001 → gain over attack, → 0.0001 at dur.
                let env: Double
                if t < v.attack {
                    env = 0.0001 * pow(v.gain / 0.0001, t / v.attack)
                } else {
                    let dt = (t - v.attack) / max(0.001, v.dur - v.attack)
                    env = v.gain * pow(0.0001 / v.gain, dt)
                }
                let idx = start + i
                if idx < Int(frames) { out[idx] += Float(s * env) }
            }
        }
        return buf
    }

    private func play(_ key: String, _ voices: [Voice]) {
        guard enabled else { return }
        startIfNeeded()
        guard !players.isEmpty else { return }
        let buf: AVAudioPCMBuffer
        if let c = cache[key] {
            buf = c
        } else {
            guard let rendered = render(voices) else { return }
            cache[key] = rendered
            buf = rendered
        }
        let p = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        p.scheduleBuffer(buf, at: nil)
        p.play()
    }

    /// The web's `seq(notes)`: [freq, dur, offset, type, gain, glideTo].
    private func seq(_ key: String, _ notes: [(Double, Double, Double, Wave, Double, Double?)]) {
        play(key, notes.map {
            Voice(freq: $0.0, dur: $0.1, type: $0.3, gain: $0.4, at: $0.2, glideTo: $0.5)
        })
    }

    /// The celebratory triad; `scale` shifts pitch (0.5 = octave down).
    private func sparkleVoices(_ off: Double, _ g: Double, _ scale: Double) -> [Voice] {
        [1568.0, 2093.0, 2637.0].enumerated().map { i, f in
            Voice(freq: f * scale, dur: 0.09, type: .sine, gain: g, at: off + Double(i) * 0.035)
        }
    }

    // MARK: - The cues (recipes verbatim)

    public func tap() { play("tap", [Voice(freq: 560, dur: 0.06, type: .sine, gain: 0.03, glideTo: 720)]) }
    public func place() { play("place", [Voice(freq: 380, dur: 0.09, type: .triangle, gain: 0.045, glideTo: 560)]) }
    public func good() {
        seq("good", [(587, 0.09, 0, .sine, 0.05, 660), (880, 0.13, 0.075, .sine, 0.048, nil)])
    }
    public func bad() {
        play("bad", [Voice(freq: 300, dur: 0.2, type: .triangle, gain: 0.05, glideTo: 200,
                           vibrato: 14, vibratoDepth: 10)])
    }
    public func save() {
        play("save", [Voice(freq: 520, dur: 0.16, type: .triangle, gain: 0.05, glideTo: 1400,
                            vibrato: 40, vibratoDepth: 35)] + sparkleVoices(0.06, 0.018, 1))
    }
    public func sameMiss() {
        seq("sameMiss", [(520, 0.14, 0, .triangle, 0.05, 440), (392, 0.22, 0.12, .triangle, 0.05, 330)])
    }
    public func purchase() {
        play("purchase", [Voice(freq: 784, dur: 0.08, gain: 0.045, glideTo: 988),
                          Voice(freq: 1175, dur: 0.12, gain: 0.04, at: 0.07)]
            + sparkleVoices(0.12, 0.016, 1))
    }
    public func death() {
        play("death", [Voice(freq: 330, dur: 0.28, type: .triangle, gain: 0.055, glideTo: 150,
                             vibrato: 12, vibratoDepth: 14)])
    }
    public func shuffle() {
        seq("shuffle", [(520, 0.05, 0, .triangle, 0.03, nil), (430, 0.05, 0.04, .triangle, 0.03, nil),
                        (360, 0.06, 0.08, .triangle, 0.028, nil), (300, 0.06, 0.12, .triangle, 0.024, nil)])
    }
    public func deal() {
        play("deal", [Voice(freq: 260, dur: 0.28, type: .sine, gain: 0.035, glideTo: 620, glideFrac: 0.9)])
    }
    public func mapAdd() {
        seq("mapAdd", [(720, 0.05, 0, .triangle, 0.03, 620), (560, 0.05, 0.05, .triangle, 0.03, 480),
                       (430, 0.08, 0.1, .sine, 0.035, 360)])
    }
    public func coin() { play("coin", [Voice(freq: 1180, dur: 0.05, type: .triangle, gain: 0.026, glideTo: 1400)]) }
    public func coinBonus() {
        seq("coinBonus", [(1047, 0.07, 0, .triangle, 0.055, 1175), (1397, 0.12, 0.06, .triangle, 0.05, nil)])
    }
    public func coinLoss() {
        seq("coinLoss", [(1175, 0.07, 0, .triangle, 0.05, 1047), (784, 0.14, 0.06, .triangle, 0.05, 698)])
    }
    /// The post-game tally: a coin ping that RISES per line.
    public func coinTallyLine(_ idx: Int) {
        let steps: [Double] = [784, 880, 988, 1047, 1175, 1319, 1397]
        let f = steps[min(max(0, idx), steps.count - 1)]
        play("tally\(min(idx, 6))", [Voice(freq: f, dur: 0.11, type: .sine, gain: 0.04, glideTo: f * 1.18)])
    }
    public func pack() {
        play("pack", [Voice(freq: 300, dur: 0.1, type: .triangle, gain: 0.05, glideTo: 700)]
            + sparkleVoices(0.09, 0.02, 1))
    }
    public func sticker() {
        play("sticker", [Voice(freq: 900, dur: 0.12, type: .sawtooth, gain: 0.022, glideTo: 1500,
                               vibrato: 30, vibratoDepth: 20),
                         Voice(freq: 420, dur: 0.06, type: .triangle, gain: 0.04, at: 0.1)])
    }
    public func refresh() {
        play("refresh", [Voice(freq: 360, dur: 0.14, type: .sine, gain: 0.038, glideTo: 780),
                         Voice(freq: 1047, dur: 0.1, type: .sine, gain: 0.035, at: 0.12)])
    }
    public func samePower() {
        play("samePower", [Voice(freq: 784, dur: 0.08, gain: 0.04, glideTo: 988),
                           Voice(freq: 1175, dur: 0.1, gain: 0.04, at: 0.07, glideTo: 1319),
                           Voice(freq: 1568, dur: 0.14, gain: 0.038, at: 0.15)]
            + sparkleVoices(0.2, 0.02, 1))
    }
    public func continueTap() {
        seq("continueTap", [(523, 0.07, 0, .sine, 0.04, 587), (784, 0.11, 0.07, .sine, 0.042, nil)])
    }

    /// DEAL WON — the little victory tune, timed to the dance (~3.4s span).
    public func dealWon() {
        play("dealWon", [
            Voice(freq: 131, dur: 0.5, type: .triangle, gain: 0.034),
            Voice(freq: 175, dur: 0.5, type: .triangle, gain: 0.03, at: 0.62),
            Voice(freq: 196, dur: 0.5, type: .triangle, gain: 0.03, at: 1.26),
            Voice(freq: 131, dur: 0.7, type: .triangle, gain: 0.034, at: 2.4),
            Voice(freq: 262, dur: 0.1, gain: 0.05, glideTo: 294),
            Voice(freq: 330, dur: 0.1, gain: 0.05, at: 0.09),
            Voice(freq: 392, dur: 0.1, gain: 0.05, at: 0.18),
            Voice(freq: 523, dur: 0.16, gain: 0.05, at: 0.27, glideTo: 587),
            Voice(freq: 392, dur: 0.09, gain: 0.044, at: 0.62),
            Voice(freq: 440, dur: 0.09, gain: 0.046, at: 0.73),
            Voice(freq: 523, dur: 0.12, gain: 0.048, at: 0.84, glideTo: 494),
            Voice(freq: 440, dur: 0.09, gain: 0.044, at: 1.04),
            Voice(freq: 494, dur: 0.09, gain: 0.046, at: 1.15),
            Voice(freq: 587, dur: 0.15, gain: 0.048, at: 1.26, glideTo: 523),
            Voice(freq: 523, dur: 0.1, gain: 0.042, at: 1.62),
            Voice(freq: 440, dur: 0.1, gain: 0.04, at: 1.74),
            Voice(freq: 392, dur: 0.12, gain: 0.038, at: 1.86),
            Voice(freq: 330, dur: 0.12, gain: 0.038, at: 2.0, glideTo: 294),
            Voice(freq: 392, dur: 0.14, gain: 0.044, at: 2.22, glideTo: 440),
            Voice(freq: 523, dur: 0.26, gain: 0.05, at: 2.4, glideTo: 587),
            Voice(freq: 659, dur: 0.4, gain: 0.044, at: 2.72, glideTo: 698),
        ] + sparkleVoices(0.34, 0.015, 0.5) + sparkleVoices(1.35, 0.013, 0.5)
          + sparkleVoices(2.45, 0.015, 0.5) + sparkleVoices(2.95, 0.011, 0.5))
    }

    public func dealLost() {
        seq("dealLost", [(494, 0.16, 0, .triangle, 0.05, 440), (392, 0.18, 0.14, .triangle, 0.05, 349),
                         (294, 0.34, 0.3, .triangle, 0.05, 233)])
    }

    /// Full RUN cleared — grander; he made it back to mama.
    public func runClear() {
        play("runClear", [
            Voice(freq: 131, dur: 0.6, type: .triangle, gain: 0.036),
            Voice(freq: 165, dur: 0.6, type: .triangle, gain: 0.032, at: 0.72),
            Voice(freq: 196, dur: 0.6, type: .triangle, gain: 0.032, at: 1.36),
            Voice(freq: 131, dur: 1.0, type: .triangle, gain: 0.038, at: 2.44),
            Voice(freq: 262, dur: 0.12, gain: 0.05, glideTo: 294),
            Voice(freq: 330, dur: 0.12, gain: 0.05, at: 0.11),
            Voice(freq: 392, dur: 0.12, gain: 0.05, at: 0.22),
            Voice(freq: 523, dur: 0.24, gain: 0.05, at: 0.33, glideTo: 659),
            Voice(freq: 392, dur: 0.1, gain: 0.046, at: 0.72),
            Voice(freq: 494, dur: 0.1, gain: 0.048, at: 0.83),
            Voice(freq: 587, dur: 0.14, gain: 0.05, at: 0.94, glideTo: 659),
            Voice(freq: 523, dur: 0.1, gain: 0.046, at: 1.14),
            Voice(freq: 587, dur: 0.1, gain: 0.048, at: 1.25),
            Voice(freq: 659, dur: 0.2, gain: 0.052, at: 1.36, glideTo: 784),
            Voice(freq: 587, dur: 0.12, gain: 0.042, at: 1.72),
            Voice(freq: 523, dur: 0.12, gain: 0.04, at: 1.86),
            Voice(freq: 440, dur: 0.14, gain: 0.038, at: 2.0, glideTo: 392),
            Voice(freq: 523, dur: 0.16, gain: 0.046, at: 2.24, glideTo: 587),
            Voice(freq: 659, dur: 0.5, gain: 0.052, at: 2.44, glideTo: 698),
            Voice(freq: 784, dur: 0.55, gain: 0.034, at: 2.6),
            Voice(freq: 1047, dur: 0.5, gain: 0.02, at: 2.72),
        ] + sparkleVoices(0.5, 0.018, 0.5) + sparkleVoices(1.4, 0.015, 0.5)
          + sparkleVoices(2.5, 0.018, 0.5) + sparkleVoices(2.95, 0.015, 0.5)
          + sparkleVoices(3.2, 0.012, 0.5))
    }

    /// NEW DECK UNLOCKED — the sparkly ta-daa.
    public func deckUnlock() {
        play("deckUnlock", [
            Voice(freq: 262, dur: 0.5, type: .triangle, gain: 0.03, at: 0.3),
            Voice(freq: 330, dur: 0.55, type: .triangle, gain: 0.03, at: 0.84),
            Voice(freq: 392, dur: 0.09, gain: 0.048, glideTo: 440),
            Voice(freq: 523, dur: 0.09, gain: 0.05, at: 0.1),
            Voice(freq: 659, dur: 0.09, gain: 0.05, at: 0.2),
            Voice(freq: 784, dur: 0.22, gain: 0.052, at: 0.3, glideTo: 880),
            Voice(freq: 659, dur: 0.1, gain: 0.044, at: 0.62),
            Voice(freq: 784, dur: 0.1, gain: 0.046, at: 0.73),
            Voice(freq: 1047, dur: 0.42, gain: 0.05, at: 0.84, glideTo: 1175),
        ] + sparkleVoices(0.35, 0.017, 0.5) + sparkleVoices(0.9, 0.018, 0.6)
          + sparkleVoices(1.25, 0.014, 0.5))
    }
}
