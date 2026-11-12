import Foundation

/// Fetches the question packs from the live website, so new questions added
/// there show up on the Apple TV without reinstalling the app. The last good
/// download is saved, and the app falls back to it (or to the questions
/// built into the app) when the website can't be reached.
enum PackLoader {
    /// One season of the real-show clue archive, as raw TSV. The game engine
    /// (archive.js) turns it into topic packs. Fetched fresh for every room.
    struct ArchiveSeason {
        let season: Int
        let tsv: String
    }
    static let archiveBase = "https://raw.githubusercontent.com/jwolle1/jeopardy_clue_dataset/main/seasons/"

    private static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("buzzworthy-packs.json")
    }

    /// Calls back on the main thread with packs JSON ([{"id":..,"data":..}]) or nil to use the
    /// built-in packs, plus a random archive season (nil if it couldn't be downloaded).
    static func load(_ done: @escaping (String?, ArchiveSeason?) -> Void) {
        let both = DispatchGroup()
        var packs: String?
        var archive: ArchiveSeason?
        both.enter()
        loadPacks { packs = $0; both.leave() }
        both.enter()
        loadArchive { archive = $0; both.leave() }
        both.notify(queue: .main) { done(packs, archive) }
    }

    /// Seasons 1 and 2 are spotty in the archive, so pick from 3 to 42.
    static func loadArchive(_ done: @escaping (ArchiveSeason?) -> Void) {
        let season = Int.random(in: 3...42)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        guard let url = URL(string: archiveBase + "season\(season).tsv") else { return done(nil) }
        URLSession(configuration: config).dataTask(with: url) { data, response, _ in
            DispatchQueue.main.async {
                guard let data = data, (response as? HTTPURLResponse)?.statusCode == 200,
                      let text = String(data: data, encoding: .utf8), text.hasPrefix("round") else { return done(nil) }
                done(ArchiveSeason(season: season, tsv: text))
            }
        }.resume()
    }

    private static func loadPacks(_ done: @escaping (String?) -> Void) {
        let finish: (String?) -> Void = { json in
            DispatchQueue.main.async {
                if let json = json {
                    if let url = cacheURL { try? json.write(to: url, atomically: true, encoding: .utf8) }
                    done(json)
                } else if let url = cacheURL, let saved = try? String(contentsOf: url, encoding: .utf8) {
                    done(saved)
                } else {
                    done(nil)
                }
            }
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        let base = "https://\(Config.joinSite)/questions/"

        guard let indexURL = URL(string: base + "index.json") else { return finish(nil) }
        session.dataTask(with: indexURL) { data, response, _ in
            guard let data = data, (response as? HTTPURLResponse)?.statusCode == 200,
                  let ids = (try? JSONSerialization.jsonObject(with: data)) as? [String], !ids.isEmpty else {
                return finish(nil)
            }
            let group = DispatchGroup()
            let lock = NSLock()
            var texts: [String: String] = [:]
            for id in ids where id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil {
                guard let url = URL(string: base + id + ".json") else { continue }
                group.enter()
                session.dataTask(with: url) { data, response, _ in
                    defer { group.leave() }
                    guard let data = data, (response as? HTTPURLResponse)?.statusCode == 200,
                          (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { return }
                    lock.lock(); texts[id] = String(decoding: data, as: UTF8.self); lock.unlock()
                }.resume()
            }
            group.notify(queue: .main) {
                let items = ids.compactMap { id in texts[id].map { #"{"id":"\#(id)","data":\#($0)}"# } }
                finish(items.isEmpty ? nil : "[" + items.joined(separator: ",") + "]")
            }
        }.resume()
    }
}
