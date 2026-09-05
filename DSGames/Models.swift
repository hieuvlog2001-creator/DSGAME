import Foundation

struct Game: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var subtitle: String
    var color: String
    var iconURL: String?
    var launchURL: String?
    var urlScheme: String?
    var bundleId: String?
    var info: String?
    var version: String?
    var ipaURL: String?
    var manifestURL: String?
    var enabled: Bool

    init(id: String, name: String, subtitle: String, color: String, iconURL: String? = nil,
         launchURL: String? = nil, urlScheme: String? = nil, bundleId: String? = nil, info: String? = nil, version: String? = nil,
         ipaURL: String? = nil, manifestURL: String? = nil, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.color = color
        self.iconURL = iconURL
        self.launchURL = launchURL
        self.urlScheme = urlScheme
        self.bundleId = bundleId
        self.info = info
        self.version = version
        self.ipaURL = ipaURL
        self.manifestURL = manifestURL
        self.enabled = enabled
    }
}

struct GameManifest: Codable {
    var version: Int
    var updatedAt: String
    var games: [Game]
}
