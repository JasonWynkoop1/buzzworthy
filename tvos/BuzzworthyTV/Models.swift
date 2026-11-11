import Foundation

/// The TV's view of the game, exactly as game.view('tv') produces it.
struct TVState: Decodable {
    var code: String
    var phase: String
    var round: Int
    var now: Double
    var deadline: Double?
    var duration: Double?
    var captainId: String?
    var hostMode: Bool
    var hostName: String
    var hostConnected: Bool
    var controllerId: String?
    var players: [Player]
    var board: [Category]?
    var clue: Clue?
    var lastResult: LastResult?
    var packs: [Pack]?
    var categoryCount: Int?
    var finalRound: FinalRound?

    enum CodingKeys: String, CodingKey {
        case code, phase, round, now, deadline, duration, captainId, hostMode, hostName, hostConnected
        case controllerId, players, board, clue, lastResult, packs, categoryCount
        case finalRound = "final"
    }

    func player(_ id: String?) -> Player? { players.first { $0.id == id } }
    func name(_ id: String?) -> String { player(id)?.name ?? "Someone" }

    /// Milliseconds left on the current timer, or nil when there is none.
    func remaining(at date: Date = Date()) -> Double? {
        guard let deadline = deadline else { return nil }
        return max(0, deadline - date.timeIntervalSince1970 * 1000)
    }
}

struct Player: Decodable, Identifiable, Equatable {
    var id: String
    var name: String
    var score: Int
    var color: String
    var connected: Bool
}

struct Category: Decodable {
    var name: String
    var clues: [Tile]
}

struct Tile: Decodable {
    var value: Int
    var used: Bool
}

struct Clue: Decodable {
    var ci: Int
    var ri: Int
    var cat: String
    var value: Int
    var dd: Bool
    var wager: Int?
    var q: String?
    var answer: String?
    var buzzedId: String?
    var tried: [String]
}

struct LastResult: Decodable, Equatable {
    var pid: String
    var answer: String?
    var correct: Bool
    var delta: Int
    var overridden: Bool
}

struct Pack: Decodable, Identifiable {
    var id: String
    var title: String
    var description: String
    var count: Int
    var selected: Bool
}

struct FinalRound: Decodable {
    var category: String
    var q: String?
    var answer: String?
    var eligible: [String]
    var wagered: [String]
    var answered: [String]
    var revealIndex: Int
    var reveals: [Reveal]
}

struct Reveal: Decodable, Identifiable {
    var id: String
    var answer: String
    var correct: Bool
    var overridden: Bool?
    var wager: Int
}

func money(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    let s = "$" + (f.string(from: NSNumber(value: abs(n))) ?? String(abs(n)))
    return n < 0 ? "-" + s : s
}
