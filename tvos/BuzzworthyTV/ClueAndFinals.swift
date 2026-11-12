import SwiftUI

// MARK: - Clue screen

struct CluePanel<Status: View>: View {
    let category: String
    let tag: String
    let question: String
    let accent: Color
    let showTimer: Bool
    let s: TVState
    @ViewBuilder let status: () -> Status

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(category.uppercased())
                    .font(Theme.body(26, .heavy))
                    .kerning(2)
                    .foregroundColor(Theme.ink)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Capsule().fill(accent))
                Spacer()
                Text(tag).font(Theme.display(40)).foregroundColor(accent)
            }
            Spacer(minLength: 20)
            Text(question)
                .font(Theme.body(70, .heavy))
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.45)
                .frame(maxWidth: 1400, alignment: .leading)
            Spacer(minLength: 20)
            HStack(alignment: .bottom) {
                status()
                Spacer()
                if showTimer { TimerRing(s: s, color: accent) }
            }
            .frame(minHeight: 150, alignment: .bottom)
        }
        .padding(.horizontal, 60).padding(.vertical, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 36).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 36).strokeBorder(accent, lineWidth: 5))
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

/// A round countdown with the seconds in the middle.
struct TimerRing: View {
    let s: TVState
    let color: Color

    var body: some View {
        TimelineView(.animation) { ctx in
            let total = max(1, s.duration ?? 1)
            let left = s.remaining(at: ctx.date) ?? 0
            let frac = min(1, left / total)
            ZStack {
                Circle().stroke(Theme.surface2, lineWidth: 14)
                Circle()
                    .trim(from: 0, to: frac)
                    .stroke(left < 4000 ? Theme.coral : color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((left / 1000).rounded(.up)))")
                    .font(Theme.display(44))
                    .monospacedDigit()
            }
            .frame(width: 140, height: 140)
        }
    }
}

struct ResultLine: View {
    let s: TVState

    var body: some View {
        if let r = s.lastResult {
            let c = r.correct ? Theme.good : Theme.bad
            HStack(spacing: 12) {
                Image(systemName: r.correct ? "checkmark.circle.fill" : "xmark.circle.fill").font(.system(size: 30))
                Text(s.name(r.pid) + (r.answer.map { " said \"\($0)\"" } ?? "")).font(Theme.body(30, .semibold)).lineLimit(1)
                Text((r.correct ? "+" : "-") + money(r.delta)).font(Theme.title(28))
                if r.overridden { Text("ruling flipped").font(Theme.body(24)).opacity(0.8) }
            }
            .foregroundColor(c)
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(Capsule().fill(c.opacity(0.15)))
        }
    }
}

/// Avatar, big name in the player's color, and a line about what they are doing.
struct PlayerCallout: View {
    let player: Player?
    let fallbackName: String
    let line: String

    var body: some View {
        let c = player.map { Color(hex: $0.color) } ?? Theme.text
        HStack(spacing: 22) {
            Avatar(name: player?.name ?? fallbackName, color: c, size: 104)
            VStack(alignment: .leading, spacing: 2) {
                Text((player?.name ?? fallbackName).uppercased()).font(Theme.display(54)).foregroundColor(c).lineLimit(1)
                Text(line).font(Theme.body(34, .semibold))
            }
        }
    }
}

struct ClueView: View {
    let s: TVState

    var body: some View {
        if let c = s.clue {
            let showTimer = s.hostMode ? s.phase == "open" : ["open", "answering", "dd-answer"].contains(s.phase)
            let buzzer = s.phase == "answering" ? s.player(c.buzzedId) : nil
            CluePanel(category: c.cat,
                      tag: c.dd ? "DAILY DOUBLE" : money(c.value),
                      question: c.q ?? "",
                      accent: buzzer.map { Color(hex: $0.color) } ?? Theme.column(c.ci),
                      showTimer: showTimer,
                      s: s) {
                status(c)
            }
            .id("clue-\(c.ci)-\(c.ri)")
        }
    }

    @ViewBuilder
    private func status(_ c: Clue) -> some View {
        switch s.phase {
        case "reading":
            Text(s.hostMode ? "\(s.hostName.isEmpty ? "The host" : s.hostName) is reading the clue. Thumbs ready." : "Get ready to buzz...")
                .font(Theme.body(34, .semibold)).foregroundColor(Theme.muted)
        case "open":
            VStack(alignment: .leading, spacing: 18) {
                ResultLine(s: s)
                BuzzNow()
            }
        case "answering":
            PlayerCallout(player: s.player(c.buzzedId), fallbackName: "Someone",
                          line: s.hostMode ? "buzzed in. Say your answer!" : "buzzed in and is answering...")
        case "dd-answer":
            PlayerCallout(player: s.player(s.controllerId), fallbackName: "Someone",
                          line: "wagered \(money(c.wager ?? 0)) and is answering...")
        case "reveal":
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "The answer")
                Text(c.answer ?? "")
                    .font(Theme.display(60))
                    .foregroundColor(Theme.yellow)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                if s.lastResult != nil {
                    ResultLine(s: s).padding(.top, 6)
                } else {
                    Text("Nobody buzzed in.").font(Theme.body(30)).foregroundColor(Theme.muted)
                }
            }
        default:
            EmptyView()
        }
    }
}

struct BuzzNow: View {
    @State private var big = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "bell.fill").font(.system(size: 36))
            Text("BUZZ IN!").font(Theme.display(48))
        }
        .foregroundColor(Theme.ink)
        .padding(.horizontal, 36).padding(.vertical, 16)
        .background(Capsule().fill(Theme.mint))
        .scaleEffect(big ? 1.06 : 1, anchor: .leading)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { big = true }
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
        text.font(Theme.body(32)).foregroundColor(Theme.muted)
    }
}

/// Slowly turning rays behind the Daily Double title.
struct Sunburst: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { g, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = max(size.width, size.height)
                let turn = ctx.date.timeIntervalSinceReferenceDate * 0.12
                let rays = 14
                for i in 0..<rays {
                    let a0 = turn + Double(i) * 2 * .pi / Double(rays)
                    let a1 = a0 + .pi / Double(rays)
                    var path = Path()
                    path.move(to: center)
                    path.addLine(to: CGPoint(x: center.x + cos(a0) * radius, y: center.y + sin(a0) * radius))
                    path.addLine(to: CGPoint(x: center.x + cos(a1) * radius, y: center.y + sin(a1) * radius))
                    path.closeSubpath()
                    g.fill(path, with: .color(color.opacity(0.09)))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 36))
    }
}

struct DDWagerView: View {
    let s: TVState
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36).fill(Theme.surface)
            Sunburst(color: Theme.yellow)
            VStack(spacing: 26) {
                VStack(spacing: -24) {
                    Text("DAILY").foregroundColor(Theme.text)
                    Text("DOUBLE").foregroundColor(Theme.yellow)
                }
                .font(Theme.display(150))
                if let c = s.clue {
                    Text(c.cat.uppercased())
                        .font(Theme.body(26, .heavy)).kerning(2)
                        .foregroundColor(Theme.ink)
                        .padding(.horizontal, 24).padding(.vertical, 10)
                        .background(Capsule().fill(Theme.column(c.ci)))
                }
                HStack(spacing: 14) {
                    if let p = s.player(s.controllerId) { Avatar(name: p.name, color: Color(hex: p.color), size: 50) }
                    Text("\(s.name(s.controllerId)) is choosing a wager...").font(Theme.body(34, .semibold))
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 36).strokeBorder(Theme.yellow, lineWidth: 5))
    }
}

/// The leaderboard: rank, avatar, name, a bar for the score.
struct Standings: View {
    let s: TVState

    var body: some View {
        let sorted = s.players.sorted { $0.score > $1.score }
        let top = max(1, sorted.first?.score ?? 1)
        let two = sorted.count > 5
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(two ? 760 : 900), spacing: 16), count: two ? 2 : 1), spacing: 12) {
            ForEach(Array(sorted.enumerated()), id: \.element.id) { i, p in
                let c = Color(hex: p.color)
                HStack(spacing: 18) {
                    Text("\(i + 1)").font(Theme.title(26)).foregroundColor(Theme.muted).frame(width: 40)
                    Avatar(name: p.name, color: c, size: 48)
                    Text(p.name).font(Theme.body(32, .semibold)).lineLimit(1)
                    Spacer()
                    Text(money(p.score)).font(Theme.display(32)).foregroundColor(p.score < 0 ? Theme.bad : Theme.text)
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Theme.surface
                            c.opacity(0.28).frame(width: geo.size.width * CGFloat(max(0, p.score)) / CGFloat(top))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                )
            }
        }
    }
}

struct RoundEndView: View {
    let s: TVState
    var body: some View {
        Splash {
            Eyebrow(text: "Round \(s.round) is done", color: Theme.yellow)
            Text(s.round == 1 ? "NEXT: DOUBLE UP" : "NEXT: THE FINAL")
                .font(Theme.display(84))
            Sub(s.round == 1 ? "Every value doubles. Lowest score picks first." : "One clue. Everyone wagers in secret.")
            Standings(s: s).padding(.top, 10)
        }
    }
}

struct StatusChips: View {
    let s: TVState
    let ids: [String]
    let done: [String]
    let doneIcon: String

    var body: some View {
        HStack(spacing: 14) {
            ForEach(ids, id: \.self) { id in
                let p = s.player(id)
                let ok = done.contains(id)
                HStack(spacing: 10) {
                    Avatar(name: p?.name ?? "?", color: Color(hex: p?.color ?? "#ffffff"), size: 40)
                    if ids.count <= 4 {
                        Text(p?.name ?? "Someone").font(Theme.body(26, .semibold)).lineLimit(1)
                    }
                    Image(systemName: ok ? doneIcon : "ellipsis")
                        .font(.system(size: 24))
                        .foregroundColor(ok ? Theme.mint : Theme.muted)
                }
                .padding(.leading, 8).padding(.trailing, 18).padding(.vertical, 8)
                .background(Capsule().fill(Theme.surface2))
            }
        }
    }
}

struct FinalWagerView: View {
    let s: TVState
    var body: some View {
        if let f = s.finalRound {
            Splash {
                Eyebrow(text: "Final Showdown", color: Theme.yellow)
                Sub("The category is")
                Text(f.category.uppercased())
                    .font(Theme.display(96))
                    .foregroundColor(Theme.yellow)
                    .minimumScaleFactor(0.4)
                    .lineLimit(2)
                Sub("Place your wager on your phone.")
                StatusChips(s: s, ids: f.eligible, done: f.wagered, doneIcon: "checkmark.circle.fill").padding(.top, 10)
            }
        }
    }
}

struct FinalAnswerView: View {
    let s: TVState
    var body: some View {
        if let f = s.finalRound {
            CluePanel(category: f.category, tag: "FINAL", question: f.q ?? "", accent: Theme.yellow, showTimer: true, s: s) {
                StatusChips(s: s, ids: f.eligible, done: f.answered, doneIcon: "lock.fill")
            }
        }
    }
}

struct RevealCards: View {
    @EnvironmentObject var host: GameHost
    let s: TVState
    let f: FinalRound

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(390), spacing: 18), count: max(1, min(f.reveals.count, 4))), spacing: 18) {
            ForEach(f.reveals) { r in
                let p = s.player(r.id)
                let c = r.correct ? Theme.good : Theme.bad
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Avatar(name: p?.name ?? "?", color: Color(hex: p?.color ?? "#ffffff"), size: 36)
                        Text(s.name(r.id)).font(Theme.body(26, .heavy)).lineLimit(1)
                        Spacer()
                        Image(systemName: r.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 30)).foregroundColor(c)
                    }
                    Text(r.answer)
                        .font(Theme.body(32, .semibold))
                        .strikethrough(!r.correct)
                        .foregroundColor(c)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    HStack {
                        Text("\(r.correct ? "+" : "-")\(money(r.wager))\(r.overridden == true ? " (flipped)" : "")")
                            .font(Theme.title(22)).foregroundColor(Theme.muted)
                        Spacer()
                        Button { host.act(["type": "finalOverride", "pid": r.id]) } label: {
                            Text("Flip").font(Theme.body(20, .semibold)).padding(.horizontal, 16).padding(.vertical, 6)
                        }
                        .buttonStyle(TVButtonStyle(corner: 12))
                    }
                }
                .multilineTextAlignment(.leading)
                .padding(20)
                .frame(width: 390, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 24).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(c.opacity(0.7), lineWidth: 3))
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

struct FinalRevealView: View {
    let s: TVState
    var body: some View {
        if let f = s.finalRound {
            Splash {
                Sub(f.q ?? "").frame(maxWidth: 1400)
                Eyebrow(text: "The answer")
                Text(f.answer ?? "")
                    .font(Theme.display(72))
                    .foregroundColor(Theme.yellow)
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                RevealCards(s: s, f: f).padding(.top, 10)
            }
        }
    }
}

/// Falling paper for the champion screen.
struct Confetti: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                for i in 0..<90 {
                    let seed = Double(i)
                    let x = (sin(seed * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    let speed = 90 + abs(sin(seed * 3.7)) * 140
                    let px = abs(x) * size.width + sin(t * 1.3 + seed) * 30
                    let py = (t * speed + seed * 97).truncatingRemainder(dividingBy: size.height + 60) - 30
                    var piece = g
                    piece.translateBy(x: px, y: py)
                    piece.rotate(by: .radians(t * 2 + seed))
                    piece.fill(Path(CGRect(x: -7, y: -11, width: 14, height: 22)), with: .color(Theme.column(i).opacity(0.85)))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

struct GameOverView: View {
    let s: TVState
    var body: some View {
        let winner = s.players.sorted { $0.score > $1.score }.first
        ZStack {
            Confetti()
            Splash {
                Eyebrow(text: "Tonight's champion", color: Theme.yellow)
                Text((winner?.name ?? "Nobody").uppercased())
                    .font(Theme.display(130))
                    .foregroundColor(winner.map { Color(hex: $0.color) } ?? Theme.text)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                if let a = s.finalRound?.answer {
                    Sub(Text("The final answer was ") + Text(a).foregroundColor(Theme.text))
                }
                Standings(s: s)
                if let f = s.finalRound, !f.reveals.isEmpty, s.players.count <= 4 {
                    RevealCards(s: s, f: f)
                }
            }
        }
    }
}
