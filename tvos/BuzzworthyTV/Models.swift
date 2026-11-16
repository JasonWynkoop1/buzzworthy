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
    /// Host mode: seconds to answer after buzzing in (0 = no clock).
    var answerTime: Int?
    var easyAvailable: Bool?
    var easyMode: Bool?
    /// Real-show archive: era buttons and the season loaded for this room.
    var hasArchive: Bool?
    var era: String?
    var eras: [String]?
    var archiveSeason: Int?
    var archiveLoading: Bool?
    var archiveError: Bool?
    /// Board builder: the category names for round 1 and round 2, or nil while picking packs.
    var draft: [[String]]?
    /// Correct answers in a row that make a player "on fire".
    var hotStreak: Int?
    /// Recent emoji reactions sent from phones.
    var reactions: [Reaction]?
    /// End-of-game awards (game over only).
    var awards: [Award]?

    enum CodingKeys: String, CodingKey {
        case code, phase, round, now, deadline, duration, captainId, hostMode, hostName, hostConnected
        case controllerId, players, board, clue, lastResult, packs, categoryCount
        case answerTime, easyAvailable, easyMode
        case hasArchive, era, eras, archiveSeason, archiveLoading, archiveError, draft
        case hotStreak, reactions, awards
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
    var streak: Int?
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
    /// How fast the winner buzzed, in ms.
    var buzzMs: Double?
    /// Everyone who buzzed on this clue, fastest first.
    var buzzes: [BuzzTime]?
    var tried: [String]
}

struct BuzzTime: Decodable, Identifiable {
    var pid: String
    var ms: Double
    var won: Bool?
    var id: String { pid }
}

struct Reaction: Decodable, Identifiable, Equatable {
    var id: Int
    var pid: String
    var e: String
}

struct Award: Decodable, Identifiable {
    var id: String
    var title: String
    var pid: String
    var detail: String
}

/// "0.31s"
func seconds(_ ms: Double) -> String { String(format: "%.2fs", ms / 1000) }

struct LastResult: Decodable, Equatable {
    var pid: String
    var answer: String?
    var correct: Bool
    var delta: Int
    var overridden: Bool
    var streak: Int?
    var dd: Bool?
}

struct Pack: Decodable, Identifiable {
    var id: String
    var title: String
    var description: String
    var count: Int
    var selected: Bool
    var easy: Bool?
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
