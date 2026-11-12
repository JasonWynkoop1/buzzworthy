import SwiftUI

// MARK: - Lobby

struct LobbyView: View {
    @EnvironmentObject var host: GameHost
    let s: TVState

    var body: some View {
        HStack(alignment: .center, spacing: 70) {
            VStack(alignment: .leading, spacing: 26) {
                Wordmark(size: 124, stacked: true)
                Text("The trivia showdown where your phone is the buzzer.")
                    .font(Theme.body(30)).foregroundColor(Theme.muted)
                Seats(s: s)
                PackPicker(s: s)
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
                        Text("Host: \(s.hostName). Answer out loud.")
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
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(314), spacing: 14), count: 3), alignment: .leading, spacing: 14) {
                ForEach(s.packs ?? []) { pk in
                    Button {
                        host.act(["type": "togglePack", "pack": pk.id])
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: pk.selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                            Text(pk.title).font(Theme.body(22, pk.selected ? .heavy : .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            Spacer(minLength: 4)
                            Text("\(pk.count)").font(Theme.body(20)).opacity(0.6)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .frame(width: 314)
                    }
                    .buttonStyle(TVButtonStyle(fill: pk.selected ? Theme.mint : Theme.surface,
                                               text: pk.selected ? Theme.ink : Theme.muted,
                                               corner: 30))
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
