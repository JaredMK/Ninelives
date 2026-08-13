import AVFoundation
import GameCore

// =============================================================================
// SOUND DESIGN RULES — read this before adding or changing a cue.
// =============================================================================
//
// 1. ONE ACTION, ONE CUE. Every distinct thing the player does or sees gets its
//    own named cue. Never reuse a cue because it "sounds about right" — if two
//    actions share a sound the player learns nothing from it. If you need a new
//    sound, add a new cue and wire it; do not overload an existing one.
//
// 2. FAMILIES. Related actions share a TIMBRE and differ only in CONTOUR:
//      • ui        — filtered-noise click + tiny low thump (button, tap, copied)
//      • paper     — filtered noise + low body: cards moving (place, bury,
//                    shuffleDeck, shufflePile, ripple, fanOpen, deal)
//      • guess     — hollow triangle blips (guessHigher / guessSame / guessLower)
//      • save      — warm rising triangle + soft sparkle (every rescue)
//      • coin      — bright triangle ting (coin, coinBonus, coinLoss, purchase,
//                    coinTallyLine)
//      • destroy   — low noise thud + falling tone (removeCard, stripSticker,
//                    swapCard, pileDestroyed, demolish, death)
//      • arcane    — clean sines stacked in fifths: items/powers firing
//      • fanfare   — the long musical tunes (dealWon, dealLost, runClear,
//                    deckUnlock, itemUnlock, jokerReward)
//
// 3. POLARITY. Good things RISE, bad things FALL. Always. A cue that ends on a
//    lower pitch than it started must represent a loss, a cost or a removal.
//
// 4. LENGTH. Every cue is <= 250ms except the fanfares. Gameplay must never
//    wait on audio.
//
// 5. HARSHNESS BUDGET. The oscillators are not band-limited, so every voice
//    runs through a one-pole low-pass (`cutoff`, default 4.2kHz) and optional
//    one-pole high-pass (`hpf`). Nothing sits at full gain in the 2–5kHz band
//    where the ear is most sensitive; the sparkle triad lives at 1047/1319/1568
//    with a 3.4kHz roll-off, not the old 1568/2093/2637 ice-pick. Vibrato is
//    capped at 6Hz / 8 cents-ish depth — anything faster reads as ring-mod buzz.
//    Attacks are 4–15ms and every voice gets a real linear release so nothing
//    clicks off. The whole mix goes through tanh saturation, so no cue can ever
//    hard-clip no matter how many voices stack.
//
// 6. PERFORMANCE. Each cue renders ONCE into a PCM buffer, cached by key, and
//    plays through a small AVAudioPlayerNode pool. Zero per-frame work, zero
//    live DSP. The long fanfares get their own dedicated node so a 3.4s tune
//    never delays the next 60ms click behind it. A per-key 45ms throttle
//    absorbs double-fires from overlapping gesture recognisers.
//
// =============================================================================

public final class Sound {

    public static let shared = Sound()

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    /// Fanfares (dealWon / runClear / unlock tunes) own this node so a 3.4s
    /// buffer never makes a following click wait its turn in the pool.
    private var longPlayer: AVAudioPlayerNode?
    private var nextPlayer = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [String: TimeInterval] = [:]
    private var started = false
    /// EVERY audio touch (session activation, buffer synthesis, scheduling)
    /// rides this serial queue — the render thread never blocks a frame.
    private let queue = DispatchQueue(label: "ninelives.sound", qos: .userInitiated)
    private var enabledCache: Bool = UserDefaults.standard.string(forKey: "ninelives.pref.sound") != "0"

    /// Post-mix output trim, then tanh saturation. `saturation` sets the
    /// ceiling (peak = 1/drive) and adds a touch of warmth to stacked voices.
    private let masterGain = 1.18
    private let saturationDrive = 2.4
    /// A cue longer than this rides the dedicated fanfare node.
    private let longCueSeconds = 1.2
    /// Same key re-fired inside this window is dropped (double-fire guard).
    private let retriggerGuard: TimeInterval = 0.045

    public var enabled: Bool {
        get { enabledCache }
        set {
            enabledCache = newValue
            UserDefaults.standard.set(newValue ? "1" : "0", forKey: "ninelives.pref.sound")
            if newValue {
                play("soundOn", clickLayer(gain: 0.026, bright: 1.0, seed: 41) + [
                    Voice(freq: 660, dur: 0.09, type: .triangle, gain: 0.04, at: 0.01,
                          glideTo: 880, attack: 0.006, cutoff: 3200),
                ])
            }
        }
    }

    private init() {}

    /// Pre-arm the session + engine off-main (called at app boot).
    public func warmUp() {
        queue.async { self.startIfNeeded() }
    }

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
            let lp = AVAudioPlayerNode()
            engine.attach(lp)
            engine.connect(lp, to: engine.mainMixerNode, format: format)
            longPlayer = lp
            try engine.start()
        } catch {
            players.removeAll()
            longPlayer = nil
        }
    }

    // MARK: - The voice

    struct Voice {
        var freq: Double
        var dur: Double = 0.12
        var type: Wave = .sine
        var gain: Double = 0.05
        var at: Double = 0
        var glideTo: Double? = nil
        var glideFrac: Double = 0.85
        var attack: Double = 0.008
        /// Linear fade over the tail — the "proper short release" that keeps
        /// cues from clicking off.
        var release: Double = 0.02
        var vibrato: Double = 0        // <= 6Hz. Faster reads as ring-mod buzz.
        var vibratoDepth: Double = 6
        /// One-pole low-pass, Hz. THE harshness control — the oscillators are
        /// not band-limited, so this is what stops them sounding like an alarm.
        var cutoff: Double = 4200
        /// Cutoff sweeps exponentially to here over `glideFrac` of the voice.
        var cutoffTo: Double? = nil
        /// One-pole high-pass, Hz (0 = off). Thins noise into paper/air.
        var hpf: Double = 0
        /// Deterministic noise seed, so a cached buffer is always identical.
        var seed: UInt64 = 0x2545F4914F6CDD1D
    }

    enum Wave { case sine, triangle, sawtooth, noise }

    /// Small deterministic PRNG — noise bursts and riffle scatter must render
    /// the same every time so the cached buffer is stable.
    private struct LCG {
        var s: UInt64
        mutating func next() -> Double {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Double(s >> 11) / Double(UInt64(1) << 53) * 2 - 1
        }
    }

    /// Render a set of voices into one mixed buffer: per-voice oscillator →
    /// one-pole LP (+ optional HP) → exponential AD envelope with a linear
    /// release, summed, then master trim + tanh saturation.
    private func render(_ voices: [Voice]) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        let total = voices.map { $0.at + $0.dur + 0.06 }.max() ?? 0.1
        let frames = AVAudioFrameCount(total * sr)
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buf.frameLength = frames
        let out = buf.floatChannelData![0]
        for i in 0..<Int(frames) { out[i] = 0 }
        let nyq = sr * 0.48

        for v in voices {
            let start = Int(v.at * sr)
            let n = Int(v.dur * sr)
            guard n > 0 else { continue }
            var phase = 0.0
            var rng = LCG(s: v.seed | 1)
            var lp = 0.0, hp = 0.0
            let f0 = v.freq
            let f1 = v.glideTo ?? v.freq
            let glideEnd = v.dur * v.glideFrac
            let c0 = min(v.cutoff, nyq)
            let c1 = min(v.cutoffTo ?? v.cutoff, nyq)
            let rel = max(0.004, min(v.release, v.dur * 0.9))
            for i in 0..<n {
                let t = Double(i) / sr
                let gt = glideEnd > 0 ? min(1, t / glideEnd) : 1

                // ---- oscillator -------------------------------------------
                let s: Double
                if v.type == .noise {
                    s = rng.next()
                } else {
                    var f = (f1 != f0) ? f0 * pow(f1 / f0, gt) : f0
                    if v.vibrato > 0 { f += sin(2 * .pi * v.vibrato * t) * v.vibratoDepth }
                    phase += 2 * .pi * f / sr
                    switch v.type {
                    case .sine: s = sin(phase)
                    case .triangle: s = (2 / Double.pi) * asin(sin(phase))
                    case .sawtooth:
                        let cyc = phase / (2 * .pi)
                        s = 2 * (cyc - (cyc + 0.5).rounded(.down))
                    case .noise: s = 0
                    }
                }

                // ---- one-pole LP (+ optional HP) --------------------------
                let fc = (c1 != c0) ? c0 * pow(c1 / c0, gt) : c0
                let a = 1 - exp(-2 * .pi * fc / sr)
                lp += a * (s - lp)
                var y = lp
                if v.hpf > 0 {
                    let b = 1 - exp(-2 * .pi * min(v.hpf, nyq) / sr)
                    hp += b * (y - hp)
                    y -= hp
                }

                // ---- envelope: exp attack, exp decay, linear release ------
                var env: Double
                if t < v.attack {
                    env = 0.0001 * pow(v.gain / 0.0001, t / max(0.0005, v.attack))
                } else {
                    let dt = (t - v.attack) / max(0.001, v.dur - v.attack)
                    env = v.gain * pow(0.0001 / v.gain, dt)
                }
                let remaining = v.dur - t
                if remaining < rel { env *= max(0, remaining / rel) }

                let idx = start + i
                if idx < Int(frames) { out[idx] += Float(y * env) }
            }
        }

        // ---- master: trim + tanh soft-clip (nothing ever hard-clips) ------
        let d = saturationDrive
        for i in 0..<Int(frames) {
            out[i] = Float(tanh(Double(out[i]) * masterGain * d) / d)
        }
        return buf
    }

    private func play(_ key: String, _ voices: [Voice]) {
        guard enabledCache else { return }
        queue.async { [self] in
            let now = CACurrentMediaTime()
            if let last = lastPlayed[key], now - last < retriggerGuard { return }
            lastPlayed[key] = now
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
            let seconds = Double(buf.frameLength) / format.sampleRate
            let p: AVAudioPlayerNode
            if seconds > longCueSeconds, let lp = longPlayer {
                p = lp
            } else {
                p = players[nextPlayer]
                nextPlayer = (nextPlayer + 1) % players.count
            }
            p.scheduleBuffer(buf, at: nil)
            p.play()
        }
    }

    /// Compact note list: [freq, dur, offset, type, gain, glideTo].
    private func seq(_ key: String, _ notes: [(Double, Double, Double, Wave, Double, Double?)],
                     cutoff: Double = 3600) {
        play(key, notes.map {
            Voice(freq: $0.0, dur: $0.1, type: $0.3, gain: $0.4, at: $0.2, glideTo: $0.5,
                  attack: 0.007, release: 0.03, cutoff: cutoff)
        })
    }

    // MARK: - Shared layers

    /// The celebratory triad. Retuned DOWN from the old 1568/2093/2637 and
    /// rolled off at 3.4kHz — that triad at full scale was the single harshest
    /// thing in the game.
    private func sparkleVoices(_ off: Double, _ g: Double, _ scale: Double) -> [Voice] {
        [1047.0, 1319.0, 1568.0].enumerated().map { i, f in
            Voice(freq: f * scale, dur: 0.09, type: .sine, gain: g, at: off + Double(i) * 0.032,
                  attack: 0.006, release: 0.032, cutoff: 3400)
        }
    }

    /// The UI-family click: an airy noise tick over a tiny low thump.
    /// `bright` scales the noise band (1.0 = a button, 1.6 = a crisp tick).
    private func clickLayer(at: Double = 0, gain: Double, bright: Double,
                            seed: UInt64, thump: Double = 300) -> [Voice] {
        [
            Voice(freq: 0, dur: 0.022, type: .noise, gain: gain, at: at,
                  attack: 0.0015, release: 0.012,
                  cutoff: 5200 * bright, cutoffTo: 2200 * bright, hpf: 1100 * bright, seed: seed),
            Voice(freq: thump, dur: 0.05, type: .sine, gain: gain * 0.8, at: at,
                  glideTo: thump * 0.8, attack: 0.004, release: 0.02, cutoff: 1100),
        ]
    }

    /// A riffle: many very short filtered-noise ticks with scattered timing,
    /// brightness and level. The backbone of every shuffle cue.
    private func riffleVoices(at: Double, count: Int, span: Double, gain: Double,
                              hp: Double, lp: Double, seed: UInt64) -> [Voice] {
        var rng = LCG(s: seed | 1)
        var out: [Voice] = []
        let step = span / Double(max(1, count - 1))
        for i in 0..<count {
            let p = Double(i) / Double(max(1, count - 1))
            let jitter = rng.next() * step * 0.55
            let bright = 1.0 + rng.next() * 0.28
            // A riffle is densest at the front and thins as the cards run out.
            let g = gain * (0.55 + 0.45 * (1 - p)) * (0.85 + 0.15 * rng.next())
            out.append(Voice(freq: 0, dur: 0.016 + abs(rng.next()) * 0.012, type: .noise,
                             gain: max(0.004, g), at: max(at, at + p * span + jitter),
                             attack: 0.0015, release: 0.008,
                             cutoff: lp * bright, cutoffTo: lp * bright * 0.6,
                             hpf: hp * bright, seed: seed &+ UInt64(i) &* 7919))
        }
        return out
    }

    // =========================================================================
    // MARK: - UI family
    // =========================================================================

    /// Any pixel button being pressed. Soft, short, unmistakably mechanical.
    public func button() {
        play("button", clickLayer(gain: 0.03, bright: 1.0, seed: 11))
    }

    /// A light selection tick: picking a pile, a chip, a row. Rises a little.
    public func tap() {
        play("tap", [
            Voice(freq: 0, dur: 0.014, type: .noise, gain: 0.016, attack: 0.0012, release: 0.008,
                  cutoff: 6800, cutoffTo: 3000, hpf: 2000, seed: 23),
            Voice(freq: 620, dur: 0.055, type: .sine, gain: 0.028, glideTo: 760,
                  attack: 0.005, release: 0.025, cutoff: 3200),
        ])
    }

    /// The CTA / CONTINUE confirm: a two-note rise. Distinct from `button()`.
    public func continueTap() {
        play("continueTap", clickLayer(gain: 0.018, bright: 1.1, seed: 31) + [
            Voice(freq: 523, dur: 0.08, type: .sine, gain: 0.042, at: 0.005, glideTo: 587,
                  attack: 0.007, release: 0.03, cutoff: 3400),
            Voice(freq: 784, dur: 0.13, type: .sine, gain: 0.04, at: 0.075,
                  attack: 0.008, release: 0.05, cutoff: 3400),
        ])
    }

    /// Something was copied to the clipboard: a tiny confirming double-blip.
    public func copied() {
        seq("copied", [(880, 0.045, 0, .sine, 0.03, nil), (1175, 0.07, 0.05, .sine, 0.028, nil)],
            cutoff: 3200)
    }

    /// The tutorial bubble stepping forward: a soft page-turn tick.
    public func tutorialAdvance() {
        play("tutorialAdvance", [
            Voice(freq: 0, dur: 0.05, type: .noise, gain: 0.022, attack: 0.006, release: 0.025,
                  cutoff: 3600, cutoffTo: 1400, hpf: 900, seed: 57),
            Voice(freq: 440, dur: 0.07, type: .sine, gain: 0.026, at: 0.02, glideTo: 523,
                  attack: 0.008, release: 0.03, cutoff: 2600),
        ])
    }

    /// The shop screen opening: a warm little door-chime, rising.
    public func storeOpen() {
        seq("storeOpen", [(392, 0.09, 0, .triangle, 0.036, 523), (659, 0.14, 0.08, .triangle, 0.034, nil)],
            cutoff: 3000)
    }

    /// The store shelf rerolled: a sweep up into a ting. (Shop-specific — the
    /// "store" MYSTERY has its own `mysteryStore`.)
    public func refresh() {
        play("refresh", riffleVoices(at: 0, count: 7, span: 0.09, gain: 0.016,
                                     hp: 1400, lp: 5200, seed: 0x51ED) + [
            Voice(freq: 360, dur: 0.14, type: .sine, gain: 0.034, glideTo: 780,
                  attack: 0.008, release: 0.04, cutoff: 3000),
            Voice(freq: 1047, dur: 0.1, type: .sine, gain: 0.03, at: 0.12,
                  attack: 0.008, release: 0.04, cutoff: 3400),
        ])
    }

    /// A pile's fan spreading open: a short paper splay.
    public func fanOpen() {
        play("fanOpen", riffleVoices(at: 0, count: 5, span: 0.075, gain: 0.034,
                                     hp: 900, lp: 4200, seed: 0xFA0) + [
            Voice(freq: 300, dur: 0.08, type: .sine, gain: 0.022, glideTo: 380,
                  attack: 0.008, release: 0.03, cutoff: 1400),
        ])
    }

    // =========================================================================
    // MARK: - Paper family (cards moving)
    // =========================================================================

    /// A CARD LANDING on a pile: a filtered-noise thwip with a low-mid body.
    /// Paper on felt, not a beep. Layered under whatever outcome cue follows.
    public func place() {
        play("place", [
            Voice(freq: 0, dur: 0.075, type: .noise, gain: 0.04, attack: 0.003, release: 0.03,
                  cutoff: 5200, cutoffTo: 1300, hpf: 700, seed: 0xCA4D),
            Voice(freq: 195, dur: 0.075, type: .sine, gain: 0.03, glideTo: 125,
                  attack: 0.005, release: 0.03, cutoff: 1200),
        ])
    }

    /// A card being tucked FACE-DOWN into a pile (a bury): duller, lower.
    public func bury() {
        play("bury", [
            Voice(freq: 0, dur: 0.09, type: .noise, gain: 0.032, attack: 0.006, release: 0.04,
                  cutoff: 2600, cutoffTo: 700, hpf: 300, seed: 0xB0),
            Voice(freq: 165, dur: 0.11, type: .triangle, gain: 0.028, glideTo: 98,
                  attack: 0.008, release: 0.045, cutoff: 900),
        ])
    }

    /// A card was DUPLICATED: the thwip, doubled, with a bright echo on top.
    public func duplicate() {
        play("duplicate", [
            Voice(freq: 0, dur: 0.05, type: .noise, gain: 0.03, attack: 0.003, release: 0.02,
                  cutoff: 5000, cutoffTo: 1400, hpf: 700, seed: 0xD1),
            Voice(freq: 0, dur: 0.05, type: .noise, gain: 0.026, at: 0.075,
                  attack: 0.003, release: 0.02, cutoff: 5000, cutoffTo: 1400, hpf: 700, seed: 0xD2),
            Voice(freq: 523, dur: 0.09, type: .sine, gain: 0.03, at: 0.075, glideTo: 784,
                  attack: 0.008, release: 0.035, cutoff: 3200),
        ])
    }

    /// The DEAL CASCADE: cards flying out one by one — a soft rising sweep
    /// with a scatter of paper ticks riding it.
    public func deal() {
        // Deliberately BARE: each card that lands during the cascade fires its
        // own `place()` thwip, so paper ticks here too would just be mush.
        play("deal", [
            Voice(freq: 240, dur: 0.22, type: .sine, gain: 0.034, glideTo: 560, glideFrac: 0.9,
                  attack: 0.014, release: 0.06, cutoff: 2400),
        ])
    }

    /// THE RIFFLE: the whole deck being shuffled for a fresh deal.
    public func shuffleDeck() {
        play("shuffleDeck", riffleVoices(at: 0, count: 22, span: 0.19, gain: 0.038,
                                         hp: 900, lp: 5200, seed: 0x5B0F) + [
            // The bridge dropping at the end: a soft low thud.
            Voice(freq: 150, dur: 0.08, type: .sine, gain: 0.03, at: 0.155, glideTo: 105,
                  attack: 0.006, release: 0.045, cutoff: 900),
        ])
    }

    /// ONE PILE shuffled in place — the riffle's little sibling: fewer ticks,
    /// shorter, thinner, no bridge thud.
    public func shufflePile() {
        play("shufflePile", riffleVoices(at: 0, count: 9, span: 0.1, gain: 0.055,
                                         hp: 1100, lp: 5600, seed: 0x91E))
    }

    /// DIAMOND RIPPLE: the same riffle timbre, but it travels — a rising
    /// shimmer rides the ticks so it reads as a wave crossing the board.
    public func ripple() {
        play("ripple", riffleVoices(at: 0, count: 14, span: 0.17, gain: 0.017,
                                    hp: 1500, lp: 6000, seed: 0x21EE) + [
            Voice(freq: 523, dur: 0.2, type: .sine, gain: 0.026, glideTo: 1047, glideFrac: 0.95,
                  attack: 0.012, release: 0.06, cutoff: 3200),
        ])
    }

    // =========================================================================
    // MARK: - Guess family
    // =========================================================================

    /// HIGHER: hollow blip that steps UP.
    public func guessHigher() {
        play("guessHigher", clickLayer(gain: 0.016, bright: 1.2, seed: 61, thump: 260) + [
            Voice(freq: 440, dur: 0.09, type: .triangle, gain: 0.034, at: 0.004, glideTo: 587,
                  attack: 0.006, release: 0.03, cutoff: 2600),
        ])
    }

    /// SAME: the same blip held LEVEL, doubled — the risky flat call.
    public func guessSame() {
        play("guessSame", clickLayer(gain: 0.016, bright: 1.2, seed: 62, thump: 260) + [
            Voice(freq: 523, dur: 0.06, type: .triangle, gain: 0.032, at: 0.004,
                  attack: 0.006, release: 0.025, cutoff: 2600),
            Voice(freq: 523, dur: 0.08, type: .triangle, gain: 0.03, at: 0.075,
                  attack: 0.006, release: 0.03, cutoff: 2600),
        ])
    }

    /// LOWER: hollow blip that steps DOWN.
    public func guessLower() {
        play("guessLower", clickLayer(gain: 0.016, bright: 1.2, seed: 63, thump: 260) + [
            Voice(freq: 440, dur: 0.09, type: .triangle, gain: 0.034, at: 0.004, glideTo: 330,
                  attack: 0.006, release: 0.03, cutoff: 2600),
        ])
    }

    /// A CORRECT guess resolved: warm rising two-note.
    public func good() {
        seq("good", [(587, 0.09, 0, .sine, 0.048, 660), (880, 0.14, 0.075, .sine, 0.044, nil)],
            cutoff: 3200)
    }

    /// A generic BAD thing (a curse landing): low, wobbling, falling.
    public func bad() {
        play("bad", [Voice(freq: 300, dur: 0.2, type: .triangle, gain: 0.05, glideTo: 200,
                           attack: 0.008, release: 0.06, vibrato: 6, vibratoDepth: 8,
                           cutoff: 1800)])
    }

    /// A PILE LOST to a wrong guess: heavy, falling, with a felt thud under it.
    public func death() {
        play("death", [
            Voice(freq: 0, dur: 0.1, type: .noise, gain: 0.026, attack: 0.004, release: 0.05,
                  cutoff: 1600, cutoffTo: 400, hpf: 150, seed: 0xDEAD),
            Voice(freq: 320, dur: 0.24, type: .triangle, gain: 0.05, glideTo: 150,
                  attack: 0.008, release: 0.09, vibrato: 5, vibratoDepth: 7, cutoff: 1600),
        ])
    }

    /// The SHOULDA-SAID-SAME sting: two falling minor steps, rueful.
    public func sameMiss() {
        seq("sameMiss", [(520, 0.12, 0, .triangle, 0.046, 440), (392, 0.14, 0.10, .triangle, 0.046, 311)],
            cutoff: 2200)
    }

    /// A JOKER hitting the board: a bright arcane wink, always safe.
    public func joker() {
        play("joker", [
            Voice(freq: 784, dur: 0.07, type: .sine, gain: 0.03, glideTo: 1175,
                  attack: 0.006, release: 0.03, cutoff: 3400),
            Voice(freq: 1175, dur: 0.11, type: .sine, gain: 0.024, at: 0.06,
                  attack: 0.008, release: 0.05, cutoff: 3400),
        ])
    }

    /// A DEAD PILE BROUGHT BACK: a rise from the cellar.
    public func revive() {
        seq("revive", [(196, 0.08, 0, .triangle, 0.042, 294), (392, 0.08, 0.07, .triangle, 0.042, nil),
                       (587, 0.11, 0.14, .sine, 0.04, 659)], cutoff: 3000)
    }

    // =========================================================================
    // MARK: - Save family (every rescue shares this warm rising shape)
    // =========================================================================

    private func saveVoices(root: Double, top: Double, sparkleGain: Double) -> [Voice] {
        [Voice(freq: root, dur: 0.16, type: .triangle, gain: 0.044, glideTo: top,
               attack: 0.01, release: 0.05, vibrato: 5, vibratoDepth: 6, cutoff: 2800)]
            + sparkleVoices(0.07, sparkleGain, 1)
    }

    /// TIE-SAFE: the guess would have died on a tie but didn't.
    public func saveTieSafe() { play("saveTieSafe", saveVoices(root: 520, top: 1046, sparkleGain: 0.015)) }
    /// GUARD sticker bounced the draw away.
    public func saveGuard() {
        play("saveGuard", [
            Voice(freq: 0, dur: 0.06, type: .noise, gain: 0.022, attack: 0.003, release: 0.03,
                  cutoff: 3000, cutoffTo: 900, hpf: 500, seed: 0x6AA),
        ] + saveVoices(root: 392, top: 784, sparkleGain: 0.013))
    }
    /// SECOND WIND: the column's one free life.
    public func saveSecondWind() { play("saveSecondWind", saveVoices(root: 330, top: 880, sparkleGain: 0.014)) }
    /// SAME CHARGE spent to survive.
    public func saveSameCharge() { play("saveSameCharge", saveVoices(root: 466, top: 932, sparkleGain: 0.016)) }

    /// A SAME CHARGE BANKED — not a rescue, a deposit: a firm click that
    /// settles UP onto a held note.
    public func sameBanked() {
        play("sameBanked", clickLayer(gain: 0.02, bright: 0.9, seed: 71, thump: 220) + [
            Voice(freq: 523, dur: 0.07, type: .triangle, gain: 0.034, at: 0.01, glideTo: 659,
                  attack: 0.006, release: 0.03, cutoff: 2800),
            Voice(freq: 784, dur: 0.15, type: .sine, gain: 0.03, at: 0.07,
                  attack: 0.01, release: 0.06, cutoff: 3000),
        ])
    }

    // =========================================================================
    // MARK: - Coin family (one timbre, different contours)
    // =========================================================================

    /// A single coin: bright but not piercing.
    public func coin() {
        play("coin", [
            Voice(freq: 1175, dur: 0.055, type: .triangle, gain: 0.026, glideTo: 1397,
                  attack: 0.004, release: 0.025, cutoff: 3600),
            Voice(freq: 2349, dur: 0.04, type: .sine, gain: 0.008, attack: 0.004, release: 0.02,
                  cutoff: 3800),
        ])
    }
    /// Coins GAINED: the ting, rising.
    public func coinBonus() {
        seq("coinBonus", [(1047, 0.07, 0, .triangle, 0.046, 1175), (1397, 0.13, 0.06, .triangle, 0.042, nil)],
            cutoff: 3600)
    }
    /// Coins SPENT or LOST: the same ting, falling.
    public func coinLoss() {
        seq("coinLoss", [(1175, 0.07, 0, .triangle, 0.044, 1047), (784, 0.15, 0.06, .triangle, 0.044, 698)],
            cutoff: 3200)
    }
    /// The post-game tally: a coin ping that RISES per line.
    public func coinTallyLine(_ idx: Int) {
        let steps: [Double] = [784, 880, 988, 1047, 1175, 1319, 1397]
        let f = steps[min(max(0, idx), steps.count - 1)]
        play("tally\(min(max(0, idx), 6))", [
            Voice(freq: f, dur: 0.12, type: .triangle, gain: 0.038, glideTo: f * 1.18,
                  attack: 0.006, release: 0.045, cutoff: 3400),
        ])
    }
    /// A STORE PURCHASE: cha-ching — coin ting into a satisfied low confirm.
    public func purchase() {
        play("purchase", [
            Voice(freq: 784, dur: 0.08, type: .triangle, gain: 0.042, glideTo: 988,
                  attack: 0.006, release: 0.03, cutoff: 3200),
            Voice(freq: 1175, dur: 0.13, type: .triangle, gain: 0.038, at: 0.07,
                  attack: 0.007, release: 0.05, cutoff: 3400),
            Voice(freq: 262, dur: 0.14, type: .sine, gain: 0.024, at: 0.07,
                  attack: 0.01, release: 0.05, cutoff: 1200),
        ] + sparkleVoices(0.09, 0.012, 1))
    }

    // =========================================================================
    // MARK: - Destroy family (low noise thud + a falling tone)
    // =========================================================================

    /// A CARD REMOVED from the deck for good: crumple and drop.
    public func removeCard() {
        play("removeCard", riffleVoices(at: 0, count: 6, span: 0.09, gain: 0.018,
                                        hp: 700, lp: 3200, seed: 0xC206) + [
            Voice(freq: 300, dur: 0.2, type: .triangle, gain: 0.038, glideTo: 165,
                  attack: 0.01, release: 0.07, cutoff: 1500),
        ])
    }

    /// A STICKER PEELED OFF a card: the crumple, but thinner and shorter.
    public func stripSticker() {
        play("stripSticker", [
            Voice(freq: 0, dur: 0.13, type: .noise, gain: 0.024, attack: 0.012, release: 0.05,
                  cutoff: 4200, cutoffTo: 1200, hpf: 1200, seed: 0x5721),
            Voice(freq: 440, dur: 0.14, type: .triangle, gain: 0.03, glideTo: 262,
                  attack: 0.01, release: 0.05, cutoff: 2200),
        ])
    }

    /// A CARD SWAPPED: one out, one in — falls, then answers by rising.
    public func swapCard() {
        play("swapCard", [
            Voice(freq: 0, dur: 0.055, type: .noise, gain: 0.022, attack: 0.004, release: 0.025,
                  cutoff: 3600, cutoffTo: 1000, hpf: 700, seed: 0x5A11),
            Voice(freq: 440, dur: 0.09, type: .triangle, gain: 0.032, glideTo: 294,
                  attack: 0.008, release: 0.035, cutoff: 2200),
            Voice(freq: 0, dur: 0.055, type: .noise, gain: 0.022, at: 0.1,
                  attack: 0.004, release: 0.025, cutoff: 3600, cutoffTo: 1000, hpf: 700, seed: 0x5A12),
            Voice(freq: 392, dur: 0.13, type: .triangle, gain: 0.034, at: 0.1, glideTo: 587,
                  attack: 0.008, release: 0.05, cutoff: 2600),
        ])
    }

    /// A PILE DESTROYED by an effect (kamikaze, heart demolish): the death
    /// family, but blunter and more sudden — no wobble, just gone.
    public func pileDestroyed() {
        play("pileDestroyed", [
            Voice(freq: 0, dur: 0.14, type: .noise, gain: 0.034, attack: 0.002, release: 0.07,
                  cutoff: 2200, cutoffTo: 300, hpf: 120, seed: 0xB00D),
            Voice(freq: 220, dur: 0.22, type: .triangle, gain: 0.044, glideTo: 82,
                  attack: 0.004, release: 0.08, cutoff: 1200),
        ])
    }

    /// A PILLAR DEMOLISHED for good: the heaviest thing in the destroy family.
    public func demolish() {
        play("demolish", [
            Voice(freq: 0, dur: 0.16, type: .noise, gain: 0.036, attack: 0.003, release: 0.09,
                  cutoff: 1600, cutoffTo: 220, hpf: 90, seed: 0xDE30),
            Voice(freq: 196, dur: 0.24, type: .triangle, gain: 0.046, glideTo: 65,
                  attack: 0.006, release: 0.1, cutoff: 1000),
            Voice(freq: 98, dur: 0.2, type: .sine, gain: 0.03, at: 0.05, glideTo: 55,
                  attack: 0.012, release: 0.09, cutoff: 700),
        ])
    }

    // =========================================================================
    // MARK: - Arcane family (items / powers firing)
    // =========================================================================

    /// A SAME-POWER proc: the signature three-step climb + sparkle.
    public func samePower() {
        play("samePower", [
            Voice(freq: 784, dur: 0.08, type: .sine, gain: 0.038, glideTo: 988,
                  attack: 0.006, release: 0.03, cutoff: 3400),
            Voice(freq: 1175, dur: 0.1, type: .sine, gain: 0.036, at: 0.07, glideTo: 1319,
                  attack: 0.007, release: 0.04, cutoff: 3400),
            Voice(freq: 1568, dur: 0.11, type: .sine, gain: 0.03, at: 0.13,
                  attack: 0.008, release: 0.05, cutoff: 3400),
        ] + sparkleVoices(0.09, 0.014, 1))
    }

    /// A REVIVE BASE firing: the arcane climb, but it lifts from the cellar.
    public func reviveBase() {
        play("reviveBase", [
            Voice(freq: 262, dur: 0.09, type: .sine, gain: 0.036, glideTo: 392,
                  attack: 0.008, release: 0.035, cutoff: 2600),
            Voice(freq: 523, dur: 0.09, type: .sine, gain: 0.034, at: 0.08, glideTo: 659,
                  attack: 0.008, release: 0.035, cutoff: 3000),
            Voice(freq: 784, dur: 0.09, type: .sine, gain: 0.032, at: 0.16, glideTo: 880,
                  attack: 0.008, release: 0.035, cutoff: 3200),
        ] + sparkleVoices(0.09, 0.013, 0.75))
    }

    /// A PILLAR firing: a short arcane two-tone, hollow fifth.
    public func pillarFire() {
        play("pillarFire", [
            Voice(freq: 330, dur: 0.08, type: .triangle, gain: 0.034, glideTo: 494,
                  attack: 0.007, release: 0.03, cutoff: 2400),
            Voice(freq: 988, dur: 0.12, type: .sine, gain: 0.022, at: 0.06,
                  attack: 0.008, release: 0.05, cutoff: 3200),
        ])
    }

    /// A BASE firing: the pillar's bigger brother — lower root, wider interval.
    public func baseFire() {
        play("baseFire", [
            Voice(freq: 220, dur: 0.1, type: .triangle, gain: 0.038, glideTo: 330,
                  attack: 0.008, release: 0.04, cutoff: 2000),
            Voice(freq: 659, dur: 0.14, type: .sine, gain: 0.026, at: 0.07, glideTo: 784,
                  attack: 0.009, release: 0.06, cutoff: 3200),
        ])
    }

    /// A CHARGED BASE PLAQUE tapped: the mechanical arm-and-fire clunk.
    public func plaqueFire() {
        play("plaqueFire", clickLayer(gain: 0.026, bright: 0.75, seed: 83, thump: 180) + [
            Voice(freq: 294, dur: 0.11, type: .triangle, gain: 0.03, at: 0.015, glideTo: 440,
                  attack: 0.006, release: 0.045, cutoff: 2200),
        ])
    }

    /// A STICKER APPLIED: a soft peel-and-press. (Was a 30Hz-vibrato sawtooth
    /// — pure buzz. Now noise + a clean rise.)
    public func sticker() {
        play("sticker", [
            Voice(freq: 0, dur: 0.1, type: .noise, gain: 0.02, attack: 0.012, release: 0.045,
                  cutoff: 4400, cutoffTo: 1600, hpf: 1400, seed: 0x571C),
            Voice(freq: 700, dur: 0.11, type: .triangle, gain: 0.024, glideTo: 1175,
                  attack: 0.008, release: 0.04, vibrato: 5, vibratoDepth: 6, cutoff: 3000),
            Voice(freq: 420, dur: 0.07, type: .triangle, gain: 0.034, at: 0.1,
                  attack: 0.006, release: 0.03, cutoff: 2200),
        ])
    }

    // =========================================================================
    // MARK: - Rewards / mysteries
    // =========================================================================

    /// A PACK opening: the tear, then the reveal lift.
    public func pack() {
        play("pack", [
            Voice(freq: 0, dur: 0.11, type: .noise, gain: 0.026, attack: 0.008, release: 0.05,
                  cutoff: 5000, cutoffTo: 1500, hpf: 1200, seed: 0x9ACC),
            Voice(freq: 300, dur: 0.12, type: .triangle, gain: 0.044, glideTo: 700,
                  attack: 0.009, release: 0.045, cutoff: 2600),
        ] + sparkleVoices(0.09, 0.016, 1))
    }

    /// The FREE-REMOVAL mystery: a pack-ish tear that resolves DOWNWARD —
    /// something is about to leave the deck, not join it.
    public func freeRemoval() {
        play("freeRemoval", [
            Voice(freq: 0, dur: 0.11, type: .noise, gain: 0.024, attack: 0.008, release: 0.05,
                  cutoff: 4000, cutoffTo: 1000, hpf: 800, seed: 0xF233),
            Voice(freq: 659, dur: 0.1, type: .triangle, gain: 0.038, glideTo: 494,
                  attack: 0.008, release: 0.04, cutoff: 2400),
            Voice(freq: 392, dur: 0.16, type: .triangle, gain: 0.036, at: 0.09, glideTo: 330,
                  attack: 0.009, release: 0.06, cutoff: 2200),
        ])
    }

    /// CARDS COLLECTED on the map: three quick paper flicks settling in.
    public func mapCollect() {
        play("mapCollect", [
            Voice(freq: 0, dur: 0.04, type: .noise, gain: 0.022, attack: 0.003, release: 0.02,
                  cutoff: 4200, cutoffTo: 1400, hpf: 900, seed: 0xA1),
            Voice(freq: 0, dur: 0.04, type: .noise, gain: 0.02, at: 0.06,
                  attack: 0.003, release: 0.02, cutoff: 4200, cutoffTo: 1400, hpf: 900, seed: 0xA2),
            Voice(freq: 0, dur: 0.045, type: .noise, gain: 0.02, at: 0.12,
                  attack: 0.003, release: 0.02, cutoff: 4200, cutoffTo: 1400, hpf: 900, seed: 0xA3),
            Voice(freq: 440, dur: 0.06, type: .sine, gain: 0.028, glideTo: 523,
                  attack: 0.006, release: 0.025, cutoff: 2600),
            Voice(freq: 523, dur: 0.06, type: .sine, gain: 0.028, at: 0.06, glideTo: 659,
                  attack: 0.006, release: 0.025, cutoff: 2600),
            Voice(freq: 659, dur: 0.11, type: .sine, gain: 0.03, at: 0.12, glideTo: 784,
                  attack: 0.007, release: 0.045, cutoff: 2800),
        ])
    }

    /// The "CARDS" MYSTERY: a surprise fan of cards — the same paper flicks,
    /// but a wider, more theatrical rise.
    public func mysteryCards() {
        play("mysteryCards", riffleVoices(at: 0, count: 8, span: 0.14, gain: 0.017,
                                          hp: 1000, lp: 4600, seed: 0x0CA5) + [
            Voice(freq: 330, dur: 0.22, type: .triangle, gain: 0.036, glideTo: 880, glideFrac: 0.9,
                  attack: 0.01, release: 0.08, cutoff: 2800),
        ])
    }

    /// The "STORE" MYSTERY: a shop appears — the store chime, bigger.
    public func mysteryStore() {
        seq("mysteryStore", [(392, 0.09, 0, .triangle, 0.038, 523),
                             (659, 0.09, 0.08, .triangle, 0.036, nil),
                             (784, 0.09, 0.16, .triangle, 0.036, 880)], cutoff: 3000)
    }

    /// The AMBUSH mystery: the deal sweep turned nasty — it falls, and growls.
    public func ambush() {
        play("ambush", [
            Voice(freq: 0, dur: 0.16, type: .noise, gain: 0.024, attack: 0.006, release: 0.08,
                  cutoff: 1800, cutoffTo: 400, hpf: 140, seed: 0xA33),
            Voice(freq: 392, dur: 0.24, type: .triangle, gain: 0.044, glideTo: 147, glideFrac: 0.9,
                  attack: 0.008, release: 0.09, vibrato: 6, vibratoDepth: 8, cutoff: 1800),
        ])
    }

    /// The JOKER MYSTERY reward: a magical, sparkly rise — a gift, not a tune.
    public func jokerReward() {
        play("jokerReward", [
            Voice(freq: 523, dur: 0.1, type: .sine, gain: 0.04, glideTo: 659,
                  attack: 0.007, release: 0.04, cutoff: 3200),
            Voice(freq: 784, dur: 0.1, type: .sine, gain: 0.04, at: 0.09, glideTo: 880,
                  attack: 0.007, release: 0.04, cutoff: 3200),
            Voice(freq: 1047, dur: 0.28, type: .sine, gain: 0.038, at: 0.18, glideTo: 1175,
                  attack: 0.009, release: 0.1, cutoff: 3400),
            Voice(freq: 262, dur: 0.5, type: .triangle, gain: 0.024, at: 0.18,
                  attack: 0.014, release: 0.16, cutoff: 1600),
        ] + sparkleVoices(0.24, 0.015, 1) + sparkleVoices(0.46, 0.011, 0.75))
    }

    // =========================================================================
    // MARK: - Map
    // =========================================================================

    /// A MAP NODE CHOSEN: a soft tick that commits — clicks, then lifts.
    public func mapSelect() {
        play("mapSelect", clickLayer(gain: 0.022, bright: 1.15, seed: 91, thump: 260) + [
            Voice(freq: 494, dur: 0.08, type: .sine, gain: 0.03, at: 0.006, glideTo: 659,
                  attack: 0.006, release: 0.03, cutoff: 3000),
        ])
    }

    /// EACH TRAVEL HOP: a tiny footstep. Fires per leg, so it must stay small.
    public func mapHop() {
        play("mapHop", [
            Voice(freq: 0, dur: 0.03, type: .noise, gain: 0.016, attack: 0.002, release: 0.014,
                  cutoff: 2400, cutoffTo: 700, hpf: 400, seed: 0x40F),
            Voice(freq: 260, dur: 0.06, type: .sine, gain: 0.022, glideTo: 200,
                  attack: 0.004, release: 0.025, cutoff: 1200),
        ])
    }

    /// ARRIVING at a node: the footstep lands and settles UP.
    public func mapArrive() {
        play("mapArrive", [
            Voice(freq: 0, dur: 0.05, type: .noise, gain: 0.022, attack: 0.003, release: 0.025,
                  cutoff: 2600, cutoffTo: 600, hpf: 300, seed: 0x4221),
            Voice(freq: 294, dur: 0.09, type: .triangle, gain: 0.032, glideTo: 392,
                  attack: 0.006, release: 0.035, cutoff: 2000),
            Voice(freq: 587, dur: 0.14, type: .sine, gain: 0.024, at: 0.08,
                  attack: 0.008, release: 0.06, cutoff: 3000),
        ])
    }

    // =========================================================================
    // MARK: - Fanfares (the only cues allowed past 250ms)
    // =========================================================================

    /// DEAL WON — the little victory tune, timed to the dance (~3.4s span).
    /// Major, rising, warm: lead sines under a 3.2kHz roll-off over a soft
    /// triangle bass.
    public func dealWon() {
        play("dealWon", fanfare([
            (131, 0.5, 0.0, 0.032), (175, 0.5, 0.62, 0.028), (196, 0.5, 1.26, 0.028),
            (131, 0.7, 2.4, 0.032),
        ], lead: [
            (262, 0.1, 0.0, 0.046, 294), (330, 0.1, 0.09, 0.046, nil), (392, 0.1, 0.18, 0.046, nil),
            (523, 0.16, 0.27, 0.046, 587),
            (392, 0.09, 0.62, 0.04, nil), (440, 0.09, 0.73, 0.042, nil),
            (523, 0.12, 0.84, 0.044, 494),
            (440, 0.09, 1.04, 0.04, nil), (494, 0.09, 1.15, 0.042, nil),
            (587, 0.15, 1.26, 0.044, 523),
            (523, 0.1, 1.62, 0.038, nil), (440, 0.1, 1.74, 0.036, nil), (392, 0.12, 1.86, 0.034, nil),
            (330, 0.12, 2.0, 0.034, 294), (392, 0.14, 2.22, 0.04, 440),
            (523, 0.26, 2.4, 0.046, 587), (659, 0.4, 2.72, 0.04, 698),
        ]) + sparkleVoices(0.34, 0.013, 0.5) + sparkleVoices(1.35, 0.011, 0.5)
          + sparkleVoices(2.45, 0.013, 0.5) + sparkleVoices(2.95, 0.01, 0.5))
    }

    /// DEAL LOST — sad and falling: a minor descent with the bass sagging under
    /// it. Short, because losing shouldn't be a performance.
    public func dealLost() {
        play("dealLost", [
            Voice(freq: 494, dur: 0.18, type: .triangle, gain: 0.046, glideTo: 440,
                  attack: 0.012, release: 0.06, cutoff: 2200),
            Voice(freq: 392, dur: 0.2, type: .triangle, gain: 0.046, at: 0.15, glideTo: 349,
                  attack: 0.012, release: 0.07, cutoff: 2000),
            Voice(freq: 294, dur: 0.42, type: .triangle, gain: 0.046, at: 0.32, glideTo: 233,
                  attack: 0.014, release: 0.16, cutoff: 1700),
            // The bass sighs down under the melody.
            Voice(freq: 147, dur: 0.34, type: .sine, gain: 0.03, at: 0.0,
                  attack: 0.02, release: 0.14, cutoff: 900),
            Voice(freq: 117, dur: 0.55, type: .sine, gain: 0.03, at: 0.32, glideTo: 98,
                  attack: 0.024, release: 0.22, cutoff: 800),
        ])
    }

    /// Full RUN cleared — grander; he made it back to mama.
    public func runClear() {
        play("runClear", fanfare([
            (131, 0.6, 0.0, 0.034), (165, 0.6, 0.72, 0.03), (196, 0.6, 1.36, 0.03),
            (131, 1.0, 2.44, 0.036),
        ], lead: [
            (262, 0.12, 0.0, 0.046, 294), (330, 0.12, 0.11, 0.046, nil), (392, 0.12, 0.22, 0.046, nil),
            (523, 0.24, 0.33, 0.046, 659),
            (392, 0.1, 0.72, 0.042, nil), (494, 0.1, 0.83, 0.044, nil),
            (587, 0.14, 0.94, 0.046, 659),
            (523, 0.1, 1.14, 0.042, nil), (587, 0.1, 1.25, 0.044, nil),
            (659, 0.2, 1.36, 0.048, 784),
            (587, 0.12, 1.72, 0.038, nil), (523, 0.12, 1.86, 0.036, nil),
            (440, 0.14, 2.0, 0.034, 392), (523, 0.16, 2.24, 0.042, 587),
            (659, 0.5, 2.44, 0.048, 698), (784, 0.55, 2.6, 0.03, nil),
            (1047, 0.5, 2.72, 0.016, nil),
        ]) + sparkleVoices(0.5, 0.016, 0.5) + sparkleVoices(1.4, 0.013, 0.5)
          + sparkleVoices(2.5, 0.016, 0.5) + sparkleVoices(2.95, 0.013, 0.5)
          + sparkleVoices(3.2, 0.01, 0.5))
    }

    /// NEW DECK UNLOCKED — the sparkly ta-daa.
    public func deckUnlock() {
        play("deckUnlock", fanfare([
            (262, 0.5, 0.3, 0.028), (330, 0.55, 0.84, 0.028),
        ], lead: [
            (392, 0.09, 0.0, 0.044, 440), (523, 0.09, 0.1, 0.046, nil), (659, 0.09, 0.2, 0.046, nil),
            (784, 0.22, 0.3, 0.048, 880),
            (659, 0.1, 0.62, 0.04, nil), (784, 0.1, 0.73, 0.042, nil),
            (1047, 0.42, 0.84, 0.044, 1175),
        ]) + sparkleVoices(0.35, 0.015, 0.5) + sparkleVoices(0.9, 0.016, 0.6)
          + sparkleVoices(1.25, 0.012, 0.5))
    }

    /// AN ITEM UNLOCKED — the deck ta-daa's shorter cousin: same shape, one
    /// bar instead of two, so the two never get confused.
    public func itemUnlock() {
        play("itemUnlock", fanfare([
            (196, 0.45, 0.18, 0.028),
        ], lead: [
            (523, 0.08, 0.0, 0.044, 587), (659, 0.08, 0.09, 0.044, nil),
            (784, 0.3, 0.18, 0.046, 880),
        ]) + sparkleVoices(0.22, 0.015, 0.6))
    }

    /// Assemble a fanfare: soft triangle bass (freq, dur, at, gain) under
    /// sine leads (freq, dur, at, gain, glideTo). Both get long releases so the
    /// tune breathes instead of chattering.
    private func fanfare(_ bass: [(Double, Double, Double, Double)],
                         lead: [(Double, Double, Double, Double, Double?)]) -> [Voice] {
        bass.map {
            Voice(freq: $0.0, dur: $0.1, type: .triangle, gain: $0.3, at: $0.2,
                  attack: 0.02, release: min(0.18, $0.1 * 0.4), cutoff: 1300)
        } + lead.map {
            Voice(freq: $0.0, dur: $0.1, type: .sine, gain: $0.3, at: $0.2, glideTo: $0.4,
                  attack: 0.008, release: min(0.12, $0.1 * 0.35), cutoff: 3200)
        }
    }
}
