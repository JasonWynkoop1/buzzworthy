import Foundation

/// Fetches the question packs from the live website, so new questions added
/// there show up on the Apple TV without reinstalling the app. The last good
/// download is saved, and the app falls back to it (or to the questions
/// built into the app) when the website can't be reached.
enum PackLoader {
    private static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("buzzworthy-packs.json")
    }

    /// Calls back on the main thread with packs JSON ([{"id":..,"data":..}]), or nil to use the built-in packs.
    static func load(_ done: @escaping (String?) -> Void) {
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
