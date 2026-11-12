import AVFoundation

/// The same little synth sounds as the web TV page, generated in code so the
/// app ships no audio files.
final class SoundPlayer {
    enum Wave { case sine, square, triangle, sawtooth }
    struct Tone {
        var freq: Double
        var dur: Double
        var wave: Wave = .sine
        var vol: Double = 0.2
        var at: Double = 0
        var slideTo: Double? = nil
    }

    var enabled = true
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let music = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var cache: [String: AVAudioPCMBuffer] = [:]

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        try? AVAudioSession.sharedInstance().setActive(true)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.attach(music)
        engine.connect(music, to: engine.mainMixerNode, format: format)
        try? engine.start()
        // The thinking music is long, so build it ahead of time off the main thread.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self, let b = self.render("think") else { return }
            DispatchQueue.main.async { self.cache["think"] = b }
        }
    }

    private static let effects: [String: [Tone]] = [
        "pick": [Tone(freq: 660, dur: 0.12, wave: .triangle), Tone(freq: 990, dur: 0.15, wave: .triangle, vol: 0.15, at: 0.08)],
        "open": [Tone(freq: 880, dur: 0.08, wave: .square, vol: 0.08)],
        "buzz": [Tone(freq: 220, dur: 0.35, wave: .sawtooth, vol: 0.18, slideTo: 440)],
        "correct": [523.0, 659, 784, 1047].enumerated().map { Tone(freq: $1, dur: 0.25, wave: .triangle, vol: 0.18, at: Double($0) * 0.09) },
        "wrong": [Tone(freq: 196, dur: 0.22, wave: .square, vol: 0.12), Tone(freq: 147, dur: 0.55, wave: .square, vol: 0.12, at: 0.2, slideTo: 98)],
        "timeout": [Tone(freq: 330, dur: 0.18, wave: .triangle, vol: 0.2), Tone(freq: 262, dur: 0.18, wave: .triangle, vol: 0.2, at: 0.2), Tone(freq: 196, dur: 0.6, wave: .triangle, vol: 0.22, at: 0.4)],
        // Daily Double: a rising sweep, then a bright chord.
        "dd": [Tone(freq: 200, dur: 0.55, wave: .sawtooth, vol: 0.09, slideTo: 1600)]
            + [587.0, 740, 880, 1175].map { Tone(freq: $0, dur: 0.9, wave: .triangle, vol: 0.12, at: 0.55) }
            + [1175.0, 1480, 1760, 2349].enumerated().map { Tone(freq: $1, dur: 0.25, wave: .sine, vol: 0.1, at: 0.7 + Double($0) * 0.08) },
        // Round start: the board lights up column by column.
        "board": [294.0, 370, 440, 587, 740, 880].enumerated().map { Tone(freq: $1, dur: 0.22, wave: .triangle, vol: 0.16, at: Double($0) * 0.11) }
            + [587.0, 880, 1175].map { Tone(freq: $0, dur: 0.8, wave: .triangle, vol: 0.12, at: 0.72) },
        "think": thinkMusic(),
        "fanfare": [523.0, 523, 523, 659, 784, 659, 784, 1047].enumerated().map { Tone(freq: $1, dur: 0.3, wave: .triangle, vol: 0.18, at: Double($0) * 0.14) },
    ]

    /// Buzzworthy's own thinking music for the Final Showdown: a ticking clock,
    /// a plucked pattern over four chords, and a bass, building every four bars.
    private static func thinkMusic() -> [Tone] {
        let beat = 0.5
        // (bass, chord tones low to high)
        let chords: [(Double, [Double])] = [
            (110.00, [220.00, 261.63, 329.63, 440.00]),   // A minor
            (87.31, [174.61, 220.00, 261.63, 349.23]),    // F
            (130.81, [261.63, 329.63, 392.00, 523.25]),   // C
            (98.00, [196.00, 246.94, 293.66, 392.00]),    // G
        ]
        let pattern = [0, 2, 1, 3, 2, 3, 1, 2]
        var out: [Tone] = []
        for bar in 0..<17 {
            let start = Double(bar) * 4 * beat
            let (bass, notes) = chords[bar % 4]
            let section = bar / 4
            for b in 0..<4 {
                let t = start + Double(b) * beat
                out.append(Tone(freq: b % 2 == 0 ? 1500 : 1100, dur: 0.05, wave: .square, vol: 0.035, at: t))   // clock
                if b == 0 || b == 2 { out.append(Tone(freq: bass, dur: 0.9, wave: .triangle, vol: 0.2, at: t)) }
            }
            if bar == 16 {   // last bar: one held chord
                for n in notes { out.append(Tone(freq: n, dur: 3.0, wave: .triangle, vol: 0.1, at: start)) }
                continue
            }
            for (i, idx) in pattern.enumerated() {
                let t = start + Double(i) * beat / 2
                out.append(Tone(freq: notes[idx], dur: 0.32, wave: .triangle, vol: 0.13, at: t))
                if section >= 2 { out.append(Tone(freq: notes[idx] * 2, dur: 0.2, wave: .sine, vol: 0.05, at: t)) }
            }
            if section % 2 == 1 {   // a slow tune on top in every other section
                let top = [notes[3], notes[2], notes[3], notes[1]]
                for (i, n) in top.enumerated() {
                    out.append(Tone(freq: n * 2, dur: 0.6, wave: .sine, vol: 0.09, at: start + Double(i) * beat))
                }
            }
        }
        return out
    }

    func startMusic(_ name: String) {
        guard enabled, let buffer = buffer(for: name) else { return }
        if !engine.isRunning { try? engine.start() }
        music.stop()
        music.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        music.play()
    }

    func stopMusic() {
        if music.isPlaying { music.stop() }
    }

    func play(_ name: String) {
        guard enabled, let buffer = buffer(for: name) else { return }
        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func buffer(for name: String) -> AVAudioPCMBuffer? {
        if let b = cache[name] { return b }
        let b = render(name)
        cache[name] = b
        return b
    }

    private func render(_ name: String) -> AVAudioPCMBuffer? {
        guard let tones = Self.effects[name] else { return nil }
        let rate = format.sampleRate
        let length = (tones.map { $0.at + $0.dur }.max() ?? 0) + 0.05
        let frames = AVAudioFrameCount(length * rate)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let out = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = frames
        for i in 0..<Int(frames) { out[i] = 0 }
        for tone in tones {
            let start = Int(tone.at * rate)
            let count = Int(tone.dur * rate)
            var phase = 0.0
            for i in 0..<count where start + i < Int(frames) {
                let t = Double(i) / rate
                var f = tone.freq
                if let to = tone.slideTo { f = tone.freq * pow(to / tone.freq, t / tone.dur) }
                phase += f / rate
                phase -= floor(phase)
                let v: Double
                switch tone.wave {
                case .sine: v = sin(2 * .pi * phase)
                case .square: v = phase < 0.5 ? 1 : -1
                case .triangle: v = 4 * abs(phase - 0.5) - 1
                case .sawtooth: v = 2 * phase - 1
                }
                let attack = 0.02
                let env = t < attack
                    ? tone.vol * (t / attack)
                    : tone.vol * pow(0.0001 / tone.vol, (t - attack) / max(0.001, tone.dur - attack))
                out[start + i] += Float(v * env)
            }
        }
        for i in 0..<Int(frames) { out[i] = max(-1, min(1, out[i])) }
        return buf
    }

    /// Picks the sound for a change in the game, like the web TV page does.
    func react(from a: TVState?, to b: TVState) {
        guard let a = a else { return }
        if a.phase != b.phase {
            if a.phase == "final-answer" { stopMusic(); play("timeout") }
            switch b.phase {
            case "final-answer": startMusic("think")
            case "board" where a.phase == "lobby" || a.phase == "round-end": play("board")
            case "reading": play("pick")
            case "open" where a.phase == "reading": play("open")
            case "answering": play("buzz")
            case "dd-wager", "final-wager": play("dd")
            case "gameover": play("fanfare")
            case "reveal" where (b.lastResult == nil || b.lastResult?.correct == false) && a.phase == "open": play("timeout")
            default: break
            }
        }
        if let rb = b.lastResult, rb != a.lastResult, ["open", "reveal"].contains(b.phase) {
            let ra = a.lastResult
            if ra == nil || ra!.pid != rb.pid || ra!.answer != rb.answer || ra!.correct != rb.correct {
                play(rb.correct ? "correct" : "wrong")
            }
        }
        if let fb = b.finalRound, let fa = a.finalRound, fb.revealIndex > fa.revealIndex,
           fb.revealIndex >= 0, fb.revealIndex < fb.reveals.count {
            play(fb.reveals[fb.revealIndex].correct ? "correct" : "wrong")
        }
    }
}
