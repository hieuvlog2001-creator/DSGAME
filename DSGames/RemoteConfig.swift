import Foundation

struct RemoteAppConfig: Codable {
    var deviceAPIURL: String?
}

enum RemoteConfig {
    private static let sources = [
        "https://hieuvlog2001-creator.github.io/DSGAME/dsgames-config.json",
        "https://raw.githubusercontent.com/hieuvlog2001-creator/DSGAME/main/dsgames-config.json",
        "https://cdn.jsdelivr.net/gh/hieuvlog2001-creator/DSGAME@main/dsgames-config.json"
    ]

    static func deviceAPIURL() async -> String? {
        for source in sources {
            if let value = await fetch(source), !value.isEmpty { return value }
        }
        return nil
    }

    private static func fetch(_ rawURL: String) async -> String? {
        guard var components = URLComponents(string: rawURL) else { return nil }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970 * 1000)))
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        return await withCheckedContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, _ in
                guard let data,
                      let http = response as? HTTPURLResponse,
                      200..<300 ~= http.statusCode,
                      let config = try? JSONDecoder().decode(RemoteAppConfig.self, from: data) else {
                    continuation.resume(returning: nil)
                    return
                }
                let value = (config.deviceAPIURL ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                continuation.resume(returning: value.isEmpty ? nil : value)
            }.resume()
        }
    }
}
