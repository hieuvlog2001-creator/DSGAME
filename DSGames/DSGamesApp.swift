import SwiftUI

@main
struct DSGamesApp: App {
    @StateObject private var gameStore = GameStore()
    @StateObject private var licenseStore = LicenseStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(gameStore)
                .environmentObject(licenseStore)
                .preferredColorScheme(.light)
        }
    }
}
