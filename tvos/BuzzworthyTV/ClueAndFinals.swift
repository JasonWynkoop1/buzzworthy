import SwiftUI

// MARK: - Clue screen

struct CluePanel<Status: View>: View {
    let category: String
    let tag: String
    let question: String
    let showTimer: Bool
    let s: TVState
    @ViewBuilder let status: () -> Status

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(RadialGradient(colors: [Color(hex: "#4b23a0"), Color(hex: "#1d0e46")], center: UnitPoint(x: 0.3, y: 0.2), startRadius: 0, endRadius: 1100))
            VStack(spacing: 0) {
                HStack {
                    Text(category.uppercased()).foregroundColor(Theme.muted)
                    Spacer()
                    Text(tag).foregroundColor(Theme.sun)
                }
                .font(Theme.display(28))
                .padding(.horizontal, 50).padding(.top, 30)
                Spacer()
                Text(question)
                    .font(Theme.body(62, .heavy))
                    .multilineTextAlignment(.center)
                    .lineSpacing(8)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 120)
                status()
                    .multilineTextAlignment(.center)
                    .padding(.top, 36)
                    .padding(.horizontal, 80)
                Spacer()
                if showTimer { TimerBar(s: s) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}

struct TimerBar: View {
    let s: TVState

    var body: some View {
        TimelineView(.animation) { ctx in
            let total = max(1, s.duration ?? 1)
            let frac = min(1, (s.remaining(at: ctx.date) ?? 0) / total)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.08))
                    Rectangle()
                        .fill(LinearGradient(colors: [Theme.hot, Theme.sun], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * frac)
                }
            }
            .frame(height: 14)
        }
    }
}

struct Countdown: View {
    let s: TVState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
            if let left = s.remaining(at: ctx.date) {
                Text("\(Int((left / 1000).rounded(.up)))")
            }
        }
    }
}

struct ResultLine: View {
    let s: TVState

    var body: some View {
        if let r = s.lastResult {
            let amt = money(r.delta)
            let said = r.answer.map { ": \"\($0)\"" } ?? ""
            let mark = r.correct ? "\u{2713} +\(amt)" : "\u{2717} -\(amt)"
            Text("\(s.name(r.pid))\(said) \(mark)\(r.overridden ? " (ruling flipped)" : "")")
                .font(Theme.body(32, .semibold))
                .foregroundColor(r.correct ? Theme.good : Theme.bad)
                .padding(.horizontal, 30).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill((r.correct ? Theme.good : Theme.bad).opacity(0.16)))
                .padding(.top, 18)
        }
    }
}

struct ClueView: View {
    let s: TVState

    var body: some View {
        if let c = s.clue {
            let showTimer = s.hostMode ? s.phase == "open" : ["open", "answering", "dd-answer"].contains(s.phase)
            CluePanel(category: c.cat, tag: c.dd ? "DAILY DOUBLE" : "$\(c.value)", question: c.q ?? "", showTimer: showTimer, s: s) {
                status(c)
            }
            .id("clue-\(c.ci)-\(c.ri)")
        }
    }

    @ViewBuilder
    private func status(_ c: Clue) -> some View {
        switch s.phase {
        case "reading":
            Text(s.hostMode ? "\(s.hostName.isEmpty ? "The host" : s.hostName) is reading the clue..." : "Get ready...")
                .font(Theme.body(36, .semibold))
        case "open":
            VStack(spacing: 0) {
                PulsingText(text: "BUZZ IN!")
                ResultLine(s: s)
            }
        case "answering":
            let who = s.player(c.buzzedId)
            HStack(spacing: 0) {
                Text(s.name(c.buzzedId)).bold().foregroundColor(who.map { Color(hex: $0.color) } ?? Theme.text)
                Text(s.hostMode ? " buzzed in! Say your answer!" : " buzzed in! Answering... ")
                if !s.hostMode { Countdown(s: s) }
            }
            .font(Theme.body(36, .semibold))
        case "dd-answer":
            HStack(spacing: 0) {
                Text(s.name(s.controllerId)).bold()
                Text(" wagered ")
                Text(money(c.wager ?? 0)).bold()
                Text(". Answering... ")
                Countdown(s: s)
            }
            .font(Theme.body(36, .semibold))
        case "reveal":
            VStack(spacing: 0) {
                Text(c.answer ?? "")
                    .font(Theme.display(60))
                    .foregroundColor(Theme.sun)
                    .transition(.scale)
                if s.lastResult != nil {
                    ResultLine(s: s)
                } else {
                    Text("Nobody buzzed in.").font(Theme.body(32)).foregroundColor(Theme.muted).padding(.top, 16)
                }
            }
        default:
            EmptyView()
        }
    }
}

struct PulsingText: View {
    let text: String
    @State private var big = false

    var body: some View {
        Text(text)
            .font(Theme.display(50))
            .foregroundColor(Theme.good)
            .scaleEffect(big ? 1.08 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { big = true }
            }
    }
}

// MARK: - Splash screens

struct Splash<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 22) { content() }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Sub: View {
    let text: Text
    init(_ s: String) { text = Text(s) }
    init(_ t: Text) { text = t }
    var body: some View {
        text.font(Theme.body(34)).foregroundColor(Theme.muted)
    }
}

struct DDWagerView: View {
    let s: TVState
    var body: some View {
        Splash {
            GradientText(text: "DAILY\nDOUBLE!", size: 130)
            Sub(s.clue?.cat ?? "")
            Sub(Text(s.name(s.controllerId)).bold().foregroundColor(Theme.text) + Text(" is choosing a wager..."))
        }
    }
}

struct Standings: View {
    let s: TVState
    var body: some View {
        VStack(spacing: 12) {
            ForEach(s.players.sorted { $0.score > $1.score }) { p in
                HStack {
                    Text(p.name)
                    Spacer()
                    Text(money(p.score)).font(Theme.display(34))
                }
                .font(Theme.body(34))
                .padding(.horizontal, 36).padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12).fill(Theme.panel)
                        .overlay(alignment: .leading) { Rectangle().fill(Color(hex: p.color)).frame(width: 9) }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                )
            }
        }
        .frame(width: 800)
    }
}

struct RoundEndView: View {
    let s: TVState
    var body: some View {
        Splash {
            GradientText(text: s.round == 1 ? "ROUND 1 DONE" : "ROUND 2 DONE", size: 100)
            Sub(s.round == 1
                ? Text("Next up: ") + Text("Double Up").bold().foregroundColor(Theme.text) + Text(", where every value doubles.")
                : Text("Next up: ") + Text("the Final Showdown").bold().foregroundColor(Theme.text) + Text("."))
            Standings(s: s)
            Sub("Press Continue (or Play/Pause on the remote) to keep going.")
        }
    }
}

struct FinalWagerView: View {
    let s: TVState
    var body: some View {
        if let f = s.finalRound {
            Splash {
                GradientText(text: "FINAL SHOWDOWN", size: 110)
                Sub("Category")
                GradientText(text: f.category, size: 72)
                Sub("Place your wagers on your phones.")
                Sub(f.eligible.map { "\(s.name($0)) \(f.wagered.contains($0) ? "\u{2713}" : "...")" }.joined(separator: "     "))
            }
        }
    }
}

struct FinalAnswerView: View {
    let s: TVState
    var body: some View {
        if let f = s.finalRound {
            CluePanel(category: f.category, tag: "FINAL SHOWDOWN", question: f.q ?? "", showTimer: true, s: s) {
                HStack(spacing: 0) {
                    Text(f.eligible.map { "\(s.name($0)) \(f.answered.contains($0) ? "\u{1F512}" : "...")" }.joined(separator: "     ") + "     ")
                    Countdown(s: s)
                }
                .font(Theme.body(34, .semibold))
            }
        }
    }
}

struct RevealCards: View {
    @EnvironmentObject var host: GameHost
    let s: TVState
    let f: FinalRound

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 400), spacing: 22)], spacing: 22) {
            ForEach(f.reveals) { r in
                VStack(alignment: .leading, spacing: 8) {
                    Text(s.name(r.id)).font(Theme.body(28, .heavy))
                    Text(r.answer)
                        .font(Theme.body(36))
                        .strikethrough(!r.correct)
                        .foregroundColor(r.correct ? Theme.good : Theme.bad)
                    HStack {
                        Text("Wagered \(money(r.wager)) \(r.correct ? "\u{2713}" : "\u{2717}")\(r.overridden == true ? " (flipped)" : "")")
                            .font(Theme.body(24)).foregroundColor(Theme.muted)
                        Spacer()
                        Button { host.act(["type": "finalOverride", "pid": r.id]) } label: {
                            Text("flip").font(Theme.body(20, .semibold)).padding(.horizontal, 14).padding(.vertical, 6)
                        }
                        .buttonStyle(TVButtonStyle(corner: 10))
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16).fill(Theme.panel)
                        .overlay(alignment: .top) { Rectangle().fill(Color(hex: s.player(r.id)?.color ?? "#ffffff")).frame(height: 8) }
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: 1600)
    }
}

struct FinalRevealView: View {
    let s: TVState
    var body: some View {
        if let f = s.finalRound {
            Splash {
                Sub(f.q ?? "")
                GradientText(text: f.answer ?? "", size: 72)
                RevealCards(s: s, f: f)
            }
        }
    }
}

struct GameOverView: View {
    let s: TVState
    var body: some View {
        let winner = s.players.sorted { $0.score > $1.score }.first
        Splash {
            Sub("And the champion is...")
            Text(winner?.name ?? "Nobody!")
                .font(Theme.display(130))
                .foregroundColor(winner.map { Color(hex: $0.color) } ?? Theme.text)
            if let a = s.finalRound?.answer {
                Sub(Text("Final answer: ") + Text(a).bold().foregroundColor(Theme.text))
            }
            Standings(s: s)
            if let f = s.finalRound, !f.reveals.isEmpty {
                RevealCards(s: s, f: f)
            }
        }
    }
}
