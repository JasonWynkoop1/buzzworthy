import SwiftUI

// MARK: - Lobby

struct LobbyView: View {
    @EnvironmentObject var host: GameHost
    let s: TVState

    var body: some View {
        HStack(alignment: .center, spacing: 70) {
            VStack(alignment: .leading, spacing: 22) {
                Text("BUZZ\nWORTHY")
                    .font(Theme.display(118))
                    .lineSpacing(-20)
                    .foregroundStyle(LinearGradient(colors: [Theme.hot, Theme.sun, Theme.cool], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("The trivia showdown where your phone is the buzzer.")
                    .font(Theme.body(30)).foregroundColor(Theme.muted)
                VStack(alignment: .leading, spacing: 8) {
                    step("1.", "Scan the code with your phone camera")
                    step("2.", "Type your name and join")
                    if s.hostMode {
                        step("3.", "Host: \(s.hostName). Players answer out loud.")
                    } else {
                        step("3.", "Want a host? They tap Join as the host. Otherwise players type answers.")
                    }
                }
                Roster(s: s)
                PackPicker(s: s)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 14) {
                if let img = QRCode.image(for: host.joinURL) {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 360, height: 360)
                        .padding(22)
                        .background(RoundedRectangle(cornerRadius: 22).fill(Color.white))
                }
                Text(s.code)
                    .font(Theme.display(96))
                    .kerning(20)
                    .foregroundColor(Theme.sun)
                Text(host.joinURL).font(Theme.body(22)).foregroundColor(Theme.muted)
            }
            .padding(40)
            .background(RoundedRectangle(cornerRadius: 32).fill(Theme.panel))
        }
    }

    private func step(_ n: String, _ text: String) -> some View {
        (Text(n + " ").foregroundColor(Theme.sun).bold() + Text(text))
            .font(Theme.body(28))
    }
}

struct Roster: View {
    let s: TVState

    var body: some View {
        if s.players.isEmpty {
            Text("Waiting for players...").font(Theme.body(30)).foregroundColor(Theme.muted)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12, alignment: .leading)], alignment: .leading, spacing: 12) {
                ForEach(s.players) { p in
                    Text(p.name + (p.id == s.captainId ? " \u{2605}" : ""))
                        .font(Theme.body(26, .heavy))
                        .foregroundColor(Color(hex: "#160b2e"))
                        .lineLimit(1)
                        .padding(.horizontal, 22).padding(.vertical, 8)
                        .background(Capsule().fill(Color(hex: p.color)))
                        .transition(.scale)
                }
            }
        }
    }
}

struct PackPicker: View {
    @EnvironmentObject var host: GameHost
    let s: TVState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Question packs (select to switch on or off), \(s.categoryCount ?? 0) categories")
                    .foregroundColor(Theme.muted)
                if (s.categoryCount ?? 0) < 12 {
                    Text("need at least 12").foregroundColor(Theme.bad)
                }
            }
            .font(Theme.body(22))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14, alignment: .leading)], alignment: .leading, spacing: 14) {
                ForEach(s.packs ?? []) { pk in
                    Button {
                        host.act(["type": "togglePack", "pack": pk.id])
                    } label: {
                        HStack(spacing: 8) {
                            Text((pk.selected ? "\u{2713} " : "") + pk.title)
                            Text("\(pk.count)").opacity(0.7)
                        }
                        .font(Theme.body(22, pk.selected ? .heavy : .semibold))
                        .foregroundColor(pk.selected ? Color(hex: "#10082a") : Theme.muted)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                    }
                    .buttonStyle(TVButtonStyle(fill: pk.selected ? Theme.cool : Theme.panel,
                                               focusedFill: pk.selected ? Theme.sun : Theme.hot.opacity(0.7)))
                }
            }
        }
    }
}

// MARK: - Board

struct BoardView: View {
    @EnvironmentObject var host: GameHost
    let s: TVState

    var body: some View {
        VStack(spacing: 10) {
            if let board = s.board {
                GeometryReader { geo in
                    let gap: CGFloat = 9
                    let w = (geo.size.width - gap * 5) / 6
                    let h = (geo.size.height - gap * 5) / 6.25
                    VStack(spacing: gap) {
                        HStack(spacing: gap) {
                            ForEach(board.indices, id: \.self) { ci in
                                Text(board[ci].name.uppercased())
                                    .font(Theme.display(24))
                                    .multilineTextAlignment(.center)
                                    .minimumScaleFactor(0.5)
                                    .padding(8)
                                    .frame(width: w, height: h * 1.25)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(
                                        LinearGradient(colors: [Color(hex: "#3a1c71"), Color(hex: "#24124a")], startPoint: .topLeading, endPoint: .bottomTrailing)))
                            }
                        }
                        ForEach(0..<5, id: \.self) { ri in
                            HStack(spacing: gap) {
                                ForEach(board.indices, id: \.self) { ci in
                                    TileView(tile: board[ci].clues[ri], width: w, height: h) {
                                        host.act(["type": "pick", "ci": ci, "ri": ri])
                                    }
                                }
                            }
                        }
                    }
                }
            }
            (Text(s.name(s.controllerId)).bold().foregroundColor(Theme.text)
             + Text(", pick a clue on your phone (or pick one here with the remote). Round \(s.round) of 2."))
                .font(Theme.body(26))
                .foregroundColor(Theme.muted)
        }
    }
}

struct TileView: View {
    let tile: Tile
    let width: CGFloat
    let height: CGFloat
    let pick: () -> Void

    var body: some View {
        if tile.used {
            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04))
                .frame(width: width, height: height)
        } else {
            Button(action: pick) {
                Text("$\(tile.value)")
                    .font(Theme.display(50))
                    .frame(width: width, height: height)
            }
            .buttonStyle(TileStyle())
        }
    }
}

struct TileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Inner(configuration: configuration)
    }

    private struct Inner: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .foregroundColor(focused ? Theme.dark : Theme.sun)
                .shadow(color: .black.opacity(focused ? 0 : 0.35), radius: 0, x: 0, y: 4)
                .background(
                    RoundedRectangle(cornerRadius: 10).fill(
                        focused
                        ? LinearGradient(colors: [Theme.sun, Color(hex: "#ffb703")], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Theme.tile1, Theme.tile2], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .scaleEffect(focused ? 1.08 : 1)
                .shadow(color: focused ? Theme.sun.opacity(0.6) : .clear, radius: 20)
                .zIndex(focused ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: focused)
        }
    }
}
