import AVFoundation

/// Plays the recorded sounds in the Sounds folder (all CC0, see CREDITS.txt).
final class SoundPlayer {
    var enabled = true
    private var players: [String: AVAudioPlayer] = [:]
    private static let names = ["pick", "open", "buzz", "correct", "wrong", "timeout", "dd", "board", "think", "fanfare"]

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        try? AVAudioSession.sharedInstance().setActive(true)
        for name in Self.names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "m4a"),
                  let p = try? AVAudioPlayer(contentsOf: url) else {
                NSLog("BUZZWORTHY_SOUND_MISSING \(name)")
                continue
            }
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

    func stopMusic() {
        players["think"]?.stop()
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
