import Foundation

enum AppConfig {
    static let manifestURL = "https://raw.githubusercontent.com/hieuvlog2001-creator/DSGAME/main/games.json"
    static let licenseURL = "https://raw.githubusercontent.com/hieuvlog2001-creator/DSGAME/main/keys.json"
    static let licenseCDNURL = "https://cdn.jsdelivr.net/gh/hieuvlog2001-creator/DSGAME@main/keys.json"
    static let supportURL = "https://github.com/hieuvlog2001-creator/DSGAME"
    // Điền URL Cloudflare Worker sau khi triển khai worker/ để Admin tự nhận thiết bị.
    // Fallback; app ưu tiên lấy URL từ dsgames-config.json để không cần rebuild khi đổi Worker.
    static let deviceAPIURL = ""

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
