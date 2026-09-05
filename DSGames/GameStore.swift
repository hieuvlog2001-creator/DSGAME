import Foundation
import SwiftUI
import UIKit

@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published var errorMessage: String?

    private let installedPrefix = "dsgames.installed."

    func installedVersion(for game: Game) -> String? {
        UserDefaults.standard.string(forKey: installedPrefix + game.id)
    }

    func markInstallRequested(for game: Game) {
        UserDefaults.standard.set(game.version ?? "", forKey: installedPrefix + game.id)
        objectWillChange.send()
    }

    func clearInstalled(for game: Game) {
        UserDefaults.standard.removeObject(forKey: installedPrefix + game.id)
        objectWillChange.send()
    }

    func openGame(_ game: Game, completion: @escaping (Bool) -> Void) {
        guard let raw = game.launchURL, let url = URL(string: raw), !raw.isEmpty else {
            completion(false)
            return
        }
        UIApplication.shared.open(url, options: [:]) { success in
            Task { @MainActor in
                if success {
                    self.markInstallRequested(for: game)
                }
                completion(success)
            }
        }
    }

    init() {
        loadBundledGames()
        Task { await refresh() }
    }

    func loadBundledGames() {
        guard let url = Bundle.main.url(forResource: "games", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(GameManifest.self, from: data) else { return }
        games = manifest.games.filter { $0.enabled }
    }

    func refresh() async {
        guard let url = URL(string: AppConfig.manifestURL), !AppConfig.manifestURL.contains("YOUR_GITHUB_USER") else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }
            let manifest = try JSONDecoder().decode(GameManifest.self, from: data)
            games = manifest.games.filter { $0.enabled }
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Không thể cập nhật danh sách game. Đang dùng dữ liệu đã có."
        }
    }
}
