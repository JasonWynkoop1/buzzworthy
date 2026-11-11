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
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var cache: [String: AVAudioPCMBuffer] = [:]

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        try? AVAudioSession.sharedInstance().setActive(true)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try? engine.start()
    }

    private static let effects: [String: [Tone]] = [
        "pick": [Tone(freq: 660, dur: 0.12, wave: .triangle), Tone(freq: 990, dur: 0.15, wave: .triangle, vol: 0.15, at: 0.08)],
        "open": [Tone(freq: 880, dur: 0.08, wave: .square, vol: 0.08)],
        "buzz": [Tone(freq: 220, dur: 0.35, wave: .sawtooth, vol: 0.18, slideTo: 440)],
        "correct": [523.0, 659, 784, 1047].enumerated().map { Tone(freq: $1, dur: 0.25, wave: .triangle, vol: 0.18, at: Double($0) * 0.09) },
        "wrong": [Tone(freq: 180, dur: 0.5, wave: .square, vol: 0.12, slideTo: 90)],
        "timeout": [Tone(freq: 300, dur: 0.25, vol: 0.15), Tone(freq: 240, dur: 0.4, vol: 0.15, at: 0.25)],
        "dd": [392.0, 523, 659, 784, 1047, 1319].enumerated().map { Tone(freq: $1, dur: 0.3, wave: .sawtooth, vol: 0.08, at: Double($0) * 0.07) },
        "fanfare": [523.0, 523, 523, 659, 784, 659, 784, 1047].enumerated().map { Tone(freq: $1, dur: 0.3, wave: .triangle, vol: 0.18, at: Double($0) * 0.14) },
    ]

    func play(_ name: String) {
        guard enabled, let buffer = buffer(for: name) else { return }
        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func buffer(for name: String) -> AVAudioPCMBuffer? {
        if let b = cache[name] { return b }
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
        cache[name] = buf
        return buf
    }

    /// Picks the sound for a change in the game, like the web TV page does.
    func react(from a: TVState?, to b: TVState) {
        guard let a = a else { return }
        if a.phase != b.phase {
            switch b.phase {
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
