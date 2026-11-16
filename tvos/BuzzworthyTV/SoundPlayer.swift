import AVFoundation

/// Plays the recorded sounds in the Sounds folder (all CC0, see CREDITS.txt).
final class SoundPlayer {
    var enabled = true
    private var players: [String: AVAudioPlayer] = [:]
    private static let names = ["pick", "open", "buzz", "correct", "wrong", "timeout", "dd", "board", "think", "fanfare", "theme"]
    private static let themeVolume: Float = 0.5
    /// Theme music in the lobby and after the champion is crowned. Remembered between launches.
    private(set) var musicOn: Bool = UserDefaults.standard.object(forKey: "musicOn") as? Bool ?? true
    private var themeWanted = false
    private var themeTimer: Timer?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        try? AVAudioSession.sharedInstance().setActive(true)
        for name in Self.names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "m4a"),
                  let p = try? AVAudioPlayer(contentsOf: url) else {
                NSLog("BUZZWORTHY_SOUND_MISSING \(name)")
                continue
            }
            if name == "theme" { p.numberOfLoops = -1; p.volume = 0 }
            p.prepareToPlay()
            players[name] = p
        }
        NSLog("BUZZWORTHY_SOUNDS_LOADED \(players.count)")
    }

    func play(_ name: String) {
        guard enabled, let p = players[name] else { return }
        p.currentTime = 0
        p.play()
    }

    func startMusic(_ name: String) { play(name) }

    func setMusic(_ on: Bool) {
        musicOn = on
        UserDefaults.standard.set(on, forKey: "musicOn")
        syncTheme()
    }

    private func wantTheme(_ on: Bool) {
        themeWanted = on
        syncTheme()
    }

    private func syncTheme() {
        guard let t = players["theme"] else { return }
        if themeWanted && musicOn && enabled {
            if !t.isPlaying {
                t.volume = 0
                t.play()
            }
            t.setVolume(Self.themeVolume, fadeDuration: 1.0)
        } else if t.isPlaying {
            t.setVolume(0, fadeDuration: 0.6)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
                guard let self = self, !(self.themeWanted && self.musicOn) else { return }
                t.pause()
            }
        }
    }

    /// The theme plays in the lobby, and comes back after the champion fanfare.
    private func pickMusic(from a: TVState?, to b: TVState) {
        if b.phase == "lobby" {
            themeTimer?.invalidate()
            wantTheme(true)
        } else if b.phase == "gameover" {
            if a?.phase != "gameover" {
                wantTheme(false)
                themeTimer?.invalidate()
                themeTimer = Timer.scheduledTimer(withTimeInterval: 5.5, repeats: false) { [weak self] _ in
                    self?.wantTheme(true)
                }
            }
        } else {
            themeTimer?.invalidate()
            if themeWanted { wantTheme(false) }
        }
    }

    func stopMusic() {
        players["think"]?.stop()
    }

    /// Picks the sound for a change in the game, like the web TV page does.
    func react(from a: TVState?, to b: TVState) {
        pickMusic(from: a, to: b)
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
