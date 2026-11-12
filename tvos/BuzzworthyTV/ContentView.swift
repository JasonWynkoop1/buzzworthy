import SwiftUI

struct ContentView: View {
    @EnvironmentObject var host: GameHost

    var body: some View {
        ZStack {
            StageBackground()

            if let s = host.state {
                GameScreen(s: s)
            } else {
                VStack(spacing: 30) {
                    Wordmark(size: 96)
                    if let problem = host.problem {
                        Text(problem).font(Theme.body(34, .semibold)).foregroundColor(Theme.bad)
                    } else {
                        ProgressView().scaleEffect(1.5)
                        Text("Setting up the game...").font(Theme.body(30)).foregroundColor(Theme.muted)
                    }
                }
            }

            if host.state != nil && !host.online {
                VStack {
                    Text("Reconnecting to the internet...")
                        .font(Theme.body(24, .semibold))
                        .foregroundColor(Theme.ink)
                        .padding(.horizontal, 28).padding(.vertical, 10)
                        .background(Capsule().fill(Theme.coral))
                    Spacer()
                }
            }
        }
        .foregroundColor(Theme.text)
        .onPlayPauseCommand { host.act("advance") }
    }
}

/// BUZZ in yellow, WORTHY in white.
struct Wordmark: View {
    var size: CGFloat = 30
    var stacked = false

    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: -size * 0.18) {
                Text("BUZZ").foregroundColor(Theme.yellow)
                Text("WORTHY").foregroundColor(Theme.text)
            }
            .font(Theme.display(size))
        } else {
            HStack(spacing: 0) {
                Text("BUZZ").foregroundColor(Theme.yellow)
                Text("WORTHY").foregroundColor(Theme.text)
            }
            .font(Theme.display(size))
        }
    }
}

struct GameScreen: View {
    @EnvironmentObject var host: GameHost
    let s: TVState

    private var showScores: Bool { !["lobby", "round-end", "gameover"].contains(s.phase) }

    var body: some View {
        VStack(spacing: 16) {
            if s.phase != "lobby" { Header(s: s) }
            Group {
                switch s.phase {
                case "lobby": LobbyView(s: s)
                case "board": BoardView(s: s)
                case "reading", "open", "answering", "reveal", "dd-answer": ClueView(s: s)
                case "dd-wager": DDWagerView(s: s)
                case "round-end": RoundEndView(s: s)
                case "final-wager": FinalWagerView(s: s)
                case "final-answer": FinalAnswerView(s: s)
                case "final-reveal": FinalRevealView(s: s)
                case "gameover": GameOverView(s: s)
                default: Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ControlBar(s: s)
            if showScores { ScoreBar(s: s) }
        }
    }
}

struct Header: View {
    let s: TVState

    private var roundLabel: String? {
        switch s.round {
        case 1: return "Round 1"
        case 2: return "Round 2 \u{00B7} Double Up"
        case 3: return "Final Showdown"
        default: return nil
        }
    }

    var body: some View {
        HStack(spacing: 24) {
            Wordmark(size: 30)
            if let label = roundLabel {
                Eyebrow(text: label, color: Theme.text, size: 18)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.surface2))
            }
            Spacer()
            Text("Join at \(Config.joinSite)/play")
                .font(Theme.body(24)).foregroundColor(Theme.muted)
            Text(s.code)
                .font(Theme.display(26))
                .kerning(4)
                .foregroundColor(Theme.ink)
                .padding(.horizontal, 18).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.yellow))
        }
    }
}

// MARK: - Scores along the bottom

struct ScoreBar: View {
    let s: TVState

    var body: some View {
        HStack(spacing: 14) {
            ForEach(s.players) { p in
                ScoreChip(p: p,
                          compact: s.players.count > 5,
                          picking: s.phase == "board" && p.id == s.controllerId,
                          buzzed: s.phase == "answering" && s.clue?.buzzedId == p.id)
            }
        }
        .padding(.top, 12)
    }
}

struct ScoreChip: View {
    let p: Player
    let compact: Bool
    let picking: Bool
    let buzzed: Bool

    var body: some View {
        let c = Color(hex: p.color)
        HStack(spacing: 14) {
            Avatar(name: p.name, color: c, size: compact ? 44 : 54)
            VStack(alignment: .leading, spacing: 0) {
                Text(p.name).font(Theme.body(compact ? 20 : 22, .semibold)).foregroundColor(Theme.muted).lineLimit(1)
                Text(money(p.score))
                    .font(Theme.display(compact ? 24 : 30))
                    .foregroundColor(p.score < 0 ? Theme.bad : Theme.text)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 14).padding(.trailing, compact ? 20 : 28).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 22).fill(buzzed ? c.opacity(0.28) : Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(picking || buzzed ? c : Theme.line, lineWidth: picking || buzzed ? 4 : 1))
        .overlay(alignment: .top) {
            if picking {
                Eyebrow(text: "Picking", color: Theme.ink, size: 13)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(c))
                    .offset(y: -13)
            }
        }
        .opacity(p.connected ? 1 : 0.4)
        .scaleEffect(buzzed ? 1.1 : 1)
        .offset(y: buzzed ? -10 : 0)
        .animation(.spring(response: 0.3), value: buzzed)
    }
}

// MARK: - Buttons for the TV's own controls

struct ControlBar: View {
    @EnvironmentObject var host: GameHost
    let s: TVState

    struct Item: Identifiable {
        let id: String
        let title: String
        let body: [String: Any]
    }

    private var buttons: [Item] {
        var b: [Item] = []
        let ph = s.phase
        if ph == "lobby" && !s.players.isEmpty { b.append(Item(id: "start", title: "Start game", body: ["type": "start"])) }
        if s.hostMode && ph == "reading" { b.append(Item(id: "open", title: "Open buzzers", body: ["type": "openNow"])) }
        if s.hostMode && (ph == "answering" || ph == "dd-answer") {
            b.append(Item(id: "right", title: "Correct", body: ["type": "judge", "correct": true]))
            b.append(Item(id: "wrong", title: "Wrong", body: ["type": "judge", "correct": false]))
        }
        if ["reading", "open", "answering", "dd-wager", "dd-answer"].contains(ph) { b.append(Item(id: "skip", title: "Skip clue", body: ["type": "skip"])) }
        if s.lastResult != nil && ["reveal", "open", "board"].contains(ph) { b.append(Item(id: "flip", title: "Flip last ruling", body: ["type": "override"])) }
        if ["reveal", "round-end", "final-wager", "final-answer", "final-reveal"].contains(ph) { b.append(Item(id: "next", title: "Continue", body: ["type": "advance"])) }
        if ph == "board" { b.append(Item(id: "end", title: "End round early", body: ["type": "endRound"])) }
        if ph == "gameover" { b.append(Item(id: "again", title: "Play again", body: ["type": "playAgain"])) }
        return b
    }

    var body: some View {
        HStack(spacing: 18) {
            ForEach(buttons) { item in
                let primary = ["start", "again"].contains(item.id)
                Button { host.act(item.body) } label: { label(item.title, big: primary) }
                    .buttonStyle(TVButtonStyle(fill: primary ? Theme.yellow : Theme.surface2,
                                               text: primary ? Theme.ink : Theme.text))
            }
            if s.phase == "lobby" {
                Button { host.newRoom() } label: { label("New room code", big: false) }
                    .buttonStyle(TVButtonStyle())
            }
            Spacer()
            if ["reveal", "round-end", "final-wager", "final-answer", "final-reveal"].contains(s.phase) {
                HStack(spacing: 8) {
                    Image(systemName: "playpause.fill")
                    Text("on the remote also continues")
                }
                .font(Theme.body(20)).foregroundColor(Theme.muted)
            }
        }
        .frame(minHeight: 64)
    }

    private func label(_ text: String, big: Bool) -> some View {
        Text(text)
            .font(Theme.body(big ? 28 : 22, big ? .heavy : .semibold))
            .padding(.horizontal, big ? 34 : 24).padding(.vertical, big ? 14 : 11)
    }
}
