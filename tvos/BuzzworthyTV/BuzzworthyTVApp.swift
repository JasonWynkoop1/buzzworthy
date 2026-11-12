import SwiftUI
import UIKit

@main
struct BuzzworthyTVApp: App {
    @StateObject private var host = GameHost()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(host)
                .onAppear {
                    // Keep the screen saver from covering the board mid-game.
                    UIApplication.shared.isIdleTimerDisabled = true
                    host.start()
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { host.appBecameActive() }
        }
    }
}
