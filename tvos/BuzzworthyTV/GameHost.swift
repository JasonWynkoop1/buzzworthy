import Foundation
import JavaScriptCore
import SwiftUI

/// Runs the Buzzworthy game engine (the same JavaScript as the website) inside
/// JavaScriptCore, and connects it to phones through Supabase Realtime.
final class GameHost: ObservableObject {
    @Published private(set) var state: TVState?
    @Published private(set) var online = false
    @Published private(set) var roomCode = ""
    @Published private(set) var problem: String?

    let sound = SoundPlayer()
    private let realtime = RealtimeClient()
    private var context: JSContext!
    private var timers: [Int: Timer] = [:]
    private var started = false

    var joinURL: String { Config.joinURL(room: roomCode) }

    func start() {
        guard !started else { return }
        started = true
        guard setUpEngine() else { return }
        realtime.onStatus = { [weak self] up in
            guard let self = self else { return }
            self.online = up
            if up { self.call("resendAll") }
        }
        realtime.onBroadcast = { [weak self] channel, event, payload in
            guard let self = self, channel == "bw:\(self.roomCode)" else { return }
            self.call("onMessage", event, payload)
        }
        realtime.connect()
        newRoom()
    }

    /// Starts a brand new room with a new code.
    func newRoom() {
        realtime.leaveAll()
        let code = call("create", packsJSON()) ?? ""
        roomCode = code
        if !code.isEmpty { realtime.join("bw:\(code)") }
    }

    func appBecameActive() {
        realtime.reconnectIfNeeded()
    }

    /// Runs a TV action, for example ["type": "advance"].
    func act(_ body: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        call("act", String(decoding: data, as: UTF8.self))
    }
    func act(_ type: String) { act(["type": type]) }

    // MARK: engine

    private func setUpEngine() -> Bool {
        guard let ctx = JSContext() else { problem = "Could not start the game engine."; return false }
        context = ctx
        ctx.exceptionHandler = { _, exception in
            NSLog("Buzzworthy JS error: \(exception?.toString() ?? "unknown")")
        }
        let native: JSValue = JSValue(newObjectIn: ctx)

        let send: @convention(block) (String, String, String) -> Void = { [weak self] channel, event, json in
            self?.realtime.send(channel, event: event, payloadJSON: json)
        }
        let stateBlock: @convention(block) (String) -> Void = { [weak self] json in
            self?.receiveState(json)
        }
        let schedule: @convention(block) (Int, Double, Bool) -> Void = { [weak self] id, ms, repeats in
            self?.schedule(id: id, ms: ms, repeats: repeats)
        }
        let cancel: @convention(block) (Int) -> Void = { [weak self] id in
            self?.timers.removeValue(forKey: id)?.invalidate()
        }
        let log: @convention(block) (String) -> Void = { text in NSLog("Buzzworthy JS: \(text)") }

        native.setObject(unsafeBitCast(send, to: AnyObject.self), forKeyedSubscript: "send" as NSString)
        native.setObject(unsafeBitCast(stateBlock, to: AnyObject.self), forKeyedSubscript: "state" as NSString)
        native.setObject(unsafeBitCast(schedule, to: AnyObject.self), forKeyedSubscript: "schedule" as NSString)
        native.setObject(unsafeBitCast(cancel, to: AnyObject.self), forKeyedSubscript: "cancel" as NSString)
        native.setObject(unsafeBitCast(log, to: AnyObject.self), forKeyedSubscript: "log" as NSString)
        ctx.setObject(native, forKeyedSubscript: "__native" as NSString)

        for file in ["shim", "judge", "game", "rules", "hub"] {
            guard let url = Bundle.main.url(forResource: file, withExtension: "js"),
                  let source = try? String(contentsOf: url, encoding: .utf8) else {
                problem = "Missing game file \(file).js. Rebuild the app in Xcode."
                return false
            }
            ctx.evaluateScript(source, withSourceURL: url)
        }
        return true
    }

    @discardableResult
    private func call(_ method: String, _ args: Any...) -> String? {
        guard let hub = context?.objectForKeyedSubscript("Hub") else { return nil }
        let result = hub.invokeMethod(method, withArguments: args)
        guard let r = result, !r.isUndefined, !r.isNull else { return nil }
        return r.toString()
    }

    private func schedule(id: Int, ms: Double, repeats: Bool) {
        timers[id]?.invalidate()
        let timer = Timer(timeInterval: max(0.001, ms / 1000), repeats: repeats) { [weak self] _ in
            guard let self = self else { return }
            if !repeats { self.timers.removeValue(forKey: id) }
            self.context?.objectForKeyedSubscript("__fire")?.call(withArguments: [id, repeats])
        }
        RunLoop.main.add(timer, forMode: .common)
        timers[id] = timer
    }

    private func packsJSON() -> String {
        var items: [String] = []
        for id in Config.packIDs {
            guard let url = Bundle.main.url(forResource: id, withExtension: "json"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            items.append(#"{"id":"\#(id)","data":\#(text)}"#)
        }
        return "[" + items.joined(separator: ",") + "]"
    }

    private func receiveState(_ json: String) {
        do {
            let next = try JSONDecoder().decode(TVState.self, from: Data(json.utf8))
            let previous = state
            withAnimation(.easeInOut(duration: 0.25)) { state = next }
            sound.react(from: previous, to: next)
        } catch {
            NSLog("Buzzworthy: could not read game state: \(error)")
        }
    }
}
