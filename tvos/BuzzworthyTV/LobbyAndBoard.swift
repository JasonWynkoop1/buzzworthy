import SwiftUI

// MARK: - Lobby

struct LobbyView: View {
    @EnvironmentObject var host: GameHost
    let s: TVState

    var body: some View {
        HStack(alignment: .center, spacing: 70) {
            // The era row and board builder need room, so the logo shrinks when they show.
            let compact = s.hasArchive == true || s.draft != nil
            VStack(alignment: .leading, spacing: compact ? 20 : 26) {
                Wordmark(size: compact ? 92 : 124, stacked: true)
                if !compact {
                    Text("The trivia showdown where your phone is the buzzer.")
                        .font(Theme.body(30)).foregroundColor(Theme.muted)
                }
                Seats(s: s)
                if s.hasArchive == true { EraPicker(s: s) }
                if let draft = s.draft, draft.count == 2 {
                    BoardBuilder(s: s, draft: draft)
                } else {
                    PackPicker(s: s)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 22) {
                Eyebrow(text: "Scan to join", color: Theme.text)
                if let img = QRCode.image(for: host.joinURL) {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 330, height: 330)
                        .padding(20)
                        .background(RoundedRectangle(cornerRadius: 26).fill(Color.white))
                }
                VStack(spacing: 12) {
                    Eyebrow(text: "or enter the room code at", size: 16)
                    Text("\(Config.joinSite)/play").font(Theme.body(26, .semibold))
                    CodeTiles(code: s.code, size: 92)
                }
            }
            .padding(.horizontal, 48).padding(.vertical, 40)
            .background(RoundedRectangle(cornerRadius: 40).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 40).stroke(Theme.line, lineWidth: 1))
        }
    }
}

/// Eight seats that fill up as players join.
struct Seats: View {
    let s: TVState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Eyebrow(text: "Players \(s.players.count) of 8")
                if s.hostMode {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                        Text("Host: \(s.hostName). Answer out loud" + ((s.answerTime ?? 0) > 0 ? " within \(s.answerTime ?? 0) seconds." : "."))
                    }
                    .font(Theme.body(20, .semibold))
                    .foregroundColor(Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.yellow))
                } else {
                    Text("Want a host to read the clues? They tap Join as the host.")
                        .font(Theme.body(20)).foregroundColor(Theme.muted)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(232), spacing: 14), count: 4), alignment: .leading, spacing: 14) {
                ForEach(0..<8, id: \.self) { i in
                    if i < s.players.count {
                        let p = s.players[i]
                        HStack(spacing: 12) {
                            Avatar(name: p.name, color: Color(hex: p.color), size: 50)
                            Text(p.name).font(Theme.body(24, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                            Spacer(minLength: 0)
                            if p.id == s.captainId && !s.hostMode {
                                Image(systemName: "star.fill").font(.system(size: 18)).foregroundColor(Theme.yellow)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(width: 232, height: 76)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface2))
                        .opacity(p.connected ? 1 : 0.5)
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
                            .frame(width: 232, height: 76)
                            .overlay(Text(i == s.players.count ? "Waiting..." : "").font(Theme.body(20)).foregroundColor(Theme.muted))
                    }
                }
            }
        }
    }
}

struct PackPicker: View {
    @EnvironmentObject var host: GameHost
    let s: TVState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Eyebrow(text: "Question packs")
                Text("\(s.categoryCount ?? 0) categories switched on")
                    .font(Theme.body(20)).foregroundColor(Theme.muted)
                if (s.categoryCount ?? 0) < 12 {
                    Text("Need at least 12").font(Theme.body(20, .semibold)).foregroundColor(Theme.bad)
                }
                Spacer(minLength: 0)
                if (s.categoryCount ?? 0) >= 12 {
                    Button {
                        host.act(["type": "previewBoard"])
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "square.grid.3x2.fill").font(.system(size: 20))
                            Text("Preview the board").font(Theme.body(20, .heavy))
                        }
                        .padding(.horizontal, 18).padding(.vertical, 8)
                    }
                    .buttonStyle(TVButtonStyle(fill: Theme.surface, text: Theme.yellow, corner: 30))
                }
                if s.easyAvailable == true {
                    let on = s.easyMode == true
                    Button {
                        host.act(["type": "toggleEasy"])
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: on ? "checkmark.circle.fill" : "star.fill").font(.system(size: 20))
                            Text(on ? "Easy mode on" : "Easy mode").font(Theme.body(20, .heavy))
                        }
                        .padding(.horizontal, 18).padding(.vertical, 8)
                    }
                    .buttonStyle(TVButtonStyle(fill: on ? Theme.yellow : Theme.surface,
                                               text: on ? Theme.ink : Theme.yellow,
                                               corner: 30))
                }
            }
            // With the archive topics there are about 15 buttons, so use four narrower columns
            // (same total width as the seats above) to keep everything on screen.
            let many = (s.packs?.count ?? 0) > 9
            let cols = many ? 4 : 3
            let w: CGFloat = many ? 232 : 314
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(w), spacing: 14), count: cols), alignment: .leading, spacing: many ? 10 : 14) {
                ForEach(s.packs ?? []) { pk in
                    Button {
                        host.act(["type": "togglePack", "pack": pk.id])
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: pk.selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: many ? 19 : 22))
                            Text(pk.title).font(Theme.body(many ? 19 : 22, pk.selected ? .heavy : .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                            Spacer(minLength: 4)
                            Text("\(pk.count)").font(Theme.body(many ? 17 : 20)).opacity(0.6)
                        }
                        .padding(.horizontal, many ? 14 : 18).padding(.vertical, many ? 9 : 11)
                        .frame(width: w)
                    }
                    .buttonStyle(TVButtonStyle(fill: pk.selected ? Theme.mint : Theme.surface,
                                               text: pk.selected ? Theme.ink : Theme.muted,
                                               corner: 30))
                }
            }
        }
    }
}

/// Era buttons for the real-show archive. Picking one loads a random season from that era.
struct EraPicker: View {
    @EnvironmentObject var host: GameHost
    let s: TVState

    static let labels = ["any": "Any era", "classic": "Classic 80s & 90s", "2000s": "2000s", "recent": "Recent"]

    static func seasonLabel(_ n: Int?) -> String {
        guard let n = n, n > 0 else { return "" }
        let start = 1983 + n
        return "Season \(n) (\(start)-\(String(format: "%02d", (start + 1) % 100)))"
    }

    var body: some View {
        HStack(spacing: 14) {
            Eyebrow(text: "Clues from")
            ForEach(s.eras ?? [], id: \.self) { e in
                let on = s.era == e
                Button {
                    host.act(["type": "setEra", "era": e])
                } label: {
                    HStack(spacing: 8) {
                        if on { Image(systemName: "checkmark").font(.system(size: 17, weight: .bold)) }
                        Text(Self.labels[e] ?? e).font(Theme.body(19, on ? .heavy : .semibold)).lineLimit(1)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .buttonStyle(TVButtonStyle(fill: on ? Theme.mint : Theme.surface,
                                           text: on ? Theme.ink : Theme.muted,
                                           corner: 30))
            }
            Group {
                if s.archiveLoading == true {
                    Text("Loading clues...").foregroundColor(Theme.muted)
                } else if s.archiveError == true {
                    Text("Could not load that era. Try again.").foregroundColor(Theme.bad)
                } else {
                    Text(Self.seasonLabel(s.archiveSeason)).foregroundColor(Theme.muted)
                }
            }
            .font(Theme.body(18)).lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

/// The 12 categories that will be played. Select one to swap it for another.
struct BoardBuilder: View {
    @EnvironmentObject var host: GameHost
    let s: TVState
    let draft: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Eyebrow(text: "Your board")
                Text("Select a category to swap it").font(Theme.body(20)).foregroundColor(Theme.muted)
                Spacer(minLength: 0)
                small("Shuffle all", icon: "shuffle") { host.act(["type": "previewBoard"]) }
                small("Back to packs", icon: "chevron.left") { host.act(["type": "clearPreview"]) }
            }
            ForEach(0..<2, id: \.self) { r in
                HStack(alignment: .top, spacing: 12) {
                    Text("R\(r + 1)").font(Theme.body(20, .heavy)).foregroundColor(Theme.yellow)
                        .frame(width: 40, alignment: .leading).padding(.top, 10)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(298), spacing: 12), count: 3), alignment: .leading, spacing: 10) {
                        ForEach(Array(draft[r].enumerated()), id: \.offset) { ci, name in
                            Button {
                                host.act(["type": "swapCategory", "r": r + 1, "ci": ci])
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 16, weight: .bold))
                                    Text(name).font(Theme.body(18, .heavy)).lineLimit(1).minimumScaleFactor(0.55)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .frame(width: 298)
                            }
                            .buttonStyle(TVButtonStyle(fill: Theme.mint, text: Theme.ink, corner: 24))
                        }
                    }
                }
            }
        }
    }

    private func small(_ title: String, icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 18))
                Text(title).font(Theme.body(19, .heavy))
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .buttonStyle(TVButtonStyle(fill: Theme.surface, text: Theme.text, corner: 30))
    }
}

// MARK: - Board

struct BoardView: View {
    @EnvironmentObject var host: GameHost
    let s: TVState

    var body: some View {
        VStack(spacing: 14) {
            if let board = s.board {
                GeometryReader { geo in
                    let gap: CGFloat = 10
                    let n = CGFloat(max(1, board.count))
                    let w = (geo.size.width - gap * (n - 1)) / n
                    let h = (geo.size.height - gap * 5) / 6.1
                    VStack(spacing: gap) {
                        HStack(spacing: gap) {
                            ForEach(board.indices, id: \.self) { ci in
                                Text(board[ci].name.uppercased())
                                    .font(Theme.body(26, .heavy))
                                    .kerning(1)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.6)
                                    .padding(.horizontal, 12)
                                    .frame(width: w, height: h * 1.1)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16).fill(Theme.surface)
                                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.column(ci)).frame(height: 7) }
                                            .clipShape(RoundedRectangle(cornerRadius: 16))
                                    )
                            }
                        }
                        ForEach(0..<5, id: \.self) { ri in
                            HStack(spacing: gap) {
                                ForEach(board.indices, id: \.self) { ci in
                                    TileView(tile: board[ci].clues[ri], color: Theme.column(ci), width: w, height: h) {
                                        host.act(["type": "pick", "ci": ci, "ri": ri])
                                    }
                                }
                            }
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                if let p = s.player(s.controllerId) {
                    Avatar(name: p.name, color: Color(hex: p.color), size: 36)
                    Text("\(p.name), it's your pick.").font(Theme.body(26, .heavy))
                }
                Text("Choose on your phone, or here with the remote.")
                    .font(Theme.body(24)).foregroundColor(Theme.muted)
            }
        }
    }
}

struct TileView: View {
    let tile: Tile
    let color: Color
    let width: CGFloat
    let height: CGFloat
    let pick: () -> Void

    var body: some View {
        if tile.used {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.line, lineWidth: 2)
                .frame(width: width, height: height)
        } else {
            Button(action: pick) {
                Text(money(tile.value))
                    .font(Theme.display(42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 10)
                    .frame(width: width, height: height)
            }
            .buttonStyle(TileStyle(color: color))
        }
    }
}

struct TileStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        Inner(configuration: configuration, color: color)
    }

    private struct Inner: View {
        let configuration: ButtonStyle.Configuration
        let color: Color
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .foregroundColor(Theme.ink)
                .background(
                    RoundedRectangle(cornerRadius: 16).fill(color)
                        .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: 18, y: 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(LinearGradient(colors: [.white.opacity(0.22), .clear, .black.opacity(0.14)], startPoint: .top, endPoint: .bottom))
                        )
                )
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white, lineWidth: focused ? 6 : 0))
                .scaleEffect(configuration.isPressed ? 1.0 : (focused ? 1.1 : 1))
                .zIndex(focused ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: focused)
        }
    }
}
