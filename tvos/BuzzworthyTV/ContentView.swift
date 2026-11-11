import SwiftUI

struct ContentView: View {
    @EnvironmentObject var host: GameHost

    var body: some View {
        ZStack {
            RadialGradient(colors: [Theme.bg2, Theme.bg], center: .top, startRadius: 0, endRadius: 1300)
                .ignoresSafeArea()

            if let s = host.state {
                GameScreen(s: s)
            } else {
                VStack(spacing: 30) {
                    GradientText(text: "BUZZWORTHY", size: 120)
                    if let problem = host.problem {
                        Text(problem).font(Theme.body(36, .semibold)).foregroundColor(Theme.bad)
                    } else {
                        ProgressView().scaleEffect(1.5)
                        Text("Setting up the game...").font(Theme.body(32)).foregroundColor(Theme.muted)
                    }
                }
            }

            if host.state != nil && !host.online {
                VStack {
                    Text("Reconnecting to the internet...")
                        .font(Theme.body(26, .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 30).padding(.vertical, 10)
                        .background(Capsule().fill(Theme.bad))
                    Spacer()
                }
            }
        }
        .foregroundColor(Theme.text)
        .onPlayPauseCommand { host.act("advance") }
    }
}

struct GameScreen: View {
    @EnvironmentObject var host: GameHost
    let s: TVState

    var body: some View {
        VStack(spacing: 14) {
            Header(s: s)
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
            if s.phase != "lobby" { ScoreBar(s: s) }
        }
    }
}

struct Header: View {
    @EnvironmentObject var host: GameHost
    let s: TVState

    var body: some View {
        HStack {
            GradientText(text: "BUZZWORTHY", size: 36,
                         gradient: LinearGradient(colors: [Theme.hot, Theme.sun], startPoint: .leading, endPoint: .trailing))
            Spacer()
            if s.phase != "lobby" {
                (Text("Join: \(Config.joinSite)/play    Room ").foregroundColor(Theme.muted)
                 + Text(s.code).font(Theme.display(32)).foregroundColor(Theme.text))
                    .font(Theme.body(26))
            }
        }
    }
}

// MARK: - Scores along the bottom

struct ScoreBar: View {
    let s: TVState

    var body: some View {
        HStack(spacing: 18) {
            ForEach(s.players) { p in
                ScoreChip(p: p,
                          picking: s.phase == "board" && p.id == s.controllerId,
                          buzzed: s.phase == "answering" && s.clue?.buzzedId == p.id)
            }
        }
        .padding(.top, 14)
    }
}

struct ScoreChip: View {
    let p: Player
    let picking: Bool
    let buzzed: Bool

    var body: some View {
        let c = Color(hex: p.color)
        VStack(spacing: 2) {
            Text(p.name).font(Theme.body(24, .semibold)).lineLimit(1)
            Text(money(p.score)).font(Theme.display(32)).foregroundColor(p.score < 0 ? Theme.bad : Theme.text)
        }
        .frame(minWidth: 200)
        .padding(.horizontal, 22).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Theme.panel)
                .overlay(alignment: .top) { Rectangle().fill(c).frame(height: 6) }
                .clipShape(RoundedRectangle(cornerRadius: 14))
        )
        .overlay(alignment: .top) {
            if picking {
                Text("PICKING").font(Theme.body(14, .heavy)).foregroundColor(Theme.dark)
                    .padding(.horizontal, 12).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.sun))
                    .offset(y: -14)
            }
        }
        .opacity(p.connected ? 1 : 0.45)
        .scaleEffect(buzzed ? 1.1 : 1)
        .offset(y: buzzed ? -12 : 0)
        .shadow(color: buzzed ? c : .clear, radius: buzzed ? 30 : 0)
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
        HStack(spacing: 20) {
            if s.phase == "lobby" {
                Button { host.newRoom() } label: { label("New room code") }
                    .buttonStyle(TVButtonStyle())
            }
            ForEach(buttons) { item in
                Button { host.act(item.body) } label: { label(item.title) }
                    .buttonStyle(TVButtonStyle(fill: item.id == "start" ? Theme.hot : Theme.panel,
                                               focusedFill: item.id == "start" ? Theme.sun : Theme.hot))
            }
            Spacer()
            if ["reveal", "round-end", "final-wager", "final-answer", "final-reveal"].contains(s.phase) {
                Text("Play/Pause on the remote = Continue").font(Theme.body(20)).foregroundColor(Theme.muted)
            }
        }
        .frame(minHeight: 70)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Theme.body(24, .bold)).padding(.horizontal, 26).padding(.vertical, 12)
    }
}
