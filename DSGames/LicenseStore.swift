import Foundation
import CryptoKit

struct LicenseManifest: Codable {
    var version: Int
    var updatedAt: String
    var licenses: [LicenseRecord]
}

struct LicenseRecord: Codable, Identifiable, Hashable {
    let id: String
    var keyHash: String
    var note: String?
    var createdAt: String
    var expiresAt: String?
    var enabled: Bool
    var keyPreview: String?
    var deviceName: String?
    var deviceId: String?
    var iosVersion: String?
    var appVersion: String?
    var activatedAt: String?
    var lastSeenAt: String?

    var isBeingUsed: Bool {
        guard let lastSeenAt, let date = ISO8601DateFormatter().date(from: lastSeenAt) else { return false }
        return Date().timeIntervalSince(date) <= 15 * 60
    }
}

@MainActor
final class LicenseStore: ObservableObject {
    enum State: Equatable {
        case checking
        case locked(String?)
        case active(LicenseRecord)
    }

    @Published private(set) var state: State = .checking
    @Published private(set) var lastChecked: Date?
    @Published var isSubmitting = false
    @Published private(set) var serverSource = ""

    private let savedHashKey = "dsgames.license.hash"
    private let cacheKey = "dsgames.license.cache"
    private let cacheCheckedKey = "dsgames.license.cache.checked"
    private let iso = ISO8601DateFormatter()

    init() {
        // Chỉ kiểm tra một lần khi khởi động; tránh hai Task mạng chạy đồng thời.
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refresh()
        }
    }

    var activeLicense: LicenseRecord? {
        if case .active(let record) = state { return record }
        return nil
    }

    var isActive: Bool { activeLicense != nil }
    var keyPreview: String { activeLicense?.keyPreview ?? "Đã kích hoạt" }
    var deviceName: String { DeviceInfo.modelName }
    var iosVersion: String { DeviceInfo.iosVersion }
    var deviceId: String { DeviceInfo.vendorIdentifier }

    func activate(key: String) async {
        let normalized = normalizeKey(key)
        guard normalized.count >= 8 else {
            state = .locked("Key không hợp lệ.")
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let hash = Self.sha256(normalized)
        // NetworkClient chạy bằng URLSession completion-handler để không bị huỷ theo
        // lifecycle của SwiftUI Task (lỗi -999 ở các bản trước).
        let result = await NetworkClient.fetchLicenses()
        switch result {
        case .success(let response):
            serverSource = response.source
            await apply(manifests: response.manifests, hash: hash, saveOnSuccess: true, plainKey: normalized)
        case .failure(let error):
            state = .locked(Self.networkMessage(error))
        }
    }

    func refresh() async {
        guard let hash = UserDefaults.standard.string(forKey: savedHashKey), !hash.isEmpty else {
            state = .locked(nil)
            return
        }

        let result = await NetworkClient.fetchLicenses()
        switch result {
        case .success(let response):
            serverSource = response.source
            await apply(manifests: response.manifests, hash: hash, saveOnSuccess: false, plainKey: nil)
        case .failure(let error):
            state = .locked(Self.networkMessage(error))
        }
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: savedHashKey)
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheCheckedKey)
        state = .locked(nil)
        serverSource = ""
    }

    func syncDeviceStatus() async {
        guard let hash = UserDefaults.standard.string(forKey: savedHashKey), !hash.isEmpty else { return }
        guard case .active = state else { return }
        await heartbeatDevice(hash: hash)
    }

    func remainingText(at date: Date = Date()) -> String {
        guard let record = activeLicense else { return "Chưa kích hoạt" }
        guard let raw = record.expiresAt, !raw.isEmpty, let expiry = iso.date(from: raw) else { return "HSD: Vĩnh viễn" }
        let seconds = max(0, Int(expiry.timeIntervalSince(date)))
        if seconds == 0 { return "HSD: Đã hết hạn" }
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "HSD: Còn \(days) ngày \(hours) giờ" }
        return "HSD: Còn \(hours) giờ \(minutes) phút"
    }

    private func apply(manifests: [LicenseManifest], hash: String, saveOnSuccess: Bool, plainKey: String?) async {
        guard let record = manifests
            .flatMap({ $0.licenses })
            .first(where: { $0.keyHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == hash.lowercased() }) else {
            clearSavedLicense()
            state = .locked("Key không tồn tại hoặc đã bị xoá.")
            return
        }

        guard record.enabled else {
            clearSavedLicense()
            state = .locked("Key đã bị Admin khóa.")
            return
        }

        if let raw = record.expiresAt, !raw.isEmpty, let expiry = iso.date(from: raw), expiry <= Date() {
            clearSavedLicense()
            state = .locked("Key đã hết hạn.")
            return
        }

        if saveOnSuccess {
            UserDefaults.standard.set(hash, forKey: savedHashKey)
        }

        var local = record
        let now = iso.string(from: Date())
        local.deviceName = DeviceInfo.modelName
        local.deviceId = DeviceInfo.vendorIdentifier
        local.iosVersion = DeviceInfo.iosVersion
        local.appVersion = AppConfig.appVersion
        local.activatedAt = local.activatedAt ?? now
        local.lastSeenAt = now
        local.keyPreview = local.keyPreview ?? "••••••••"
        cache(local)

        if let plainKey {
            await syncDevice(key: plainKey, record: local)
        }
        // Luôn gửi heartbeat bằng hash đã lưu, kể cả khi Key đã được kích hoạt từ trước.
        await heartbeatDevice(hash: hash)

        lastChecked = Date()
        state = .active(local)
    }

    private func normalizeKey(_ key: String) -> String {
        key
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private func cache(_ record: LicenseRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheCheckedKey)
    }

    private func clearSavedLicense() {
        UserDefaults.standard.removeObject(forKey: savedHashKey)
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheCheckedKey)
    }

    private func syncDevice(key: String, record: LicenseRecord) async {
        let configured = await RemoteConfig.deviceAPIURL() ?? AppConfig.deviceAPIURL
        guard !configured.isEmpty,
              let url = URL(string: configured + "/register") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String:String] = [
            "key": key,
            "deviceId": DeviceInfo.vendorIdentifier,
            "deviceName": DeviceInfo.modelName,
            "iosVersion": DeviceInfo.iosVersion,
            "appVersion": AppConfig.appVersion
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = await NetworkClient.perform(request: request)
    }

    private func heartbeatDevice(hash: String) async {
        let configured = await RemoteConfig.deviceAPIURL() ?? AppConfig.deviceAPIURL
        guard !configured.isEmpty, let url = URL(string: configured + "/heartbeat") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "keyHash": hash,
            "deviceId": DeviceInfo.vendorIdentifier,
            "deviceName": DeviceInfo.modelName,
            "iosVersion": DeviceInfo.iosVersion,
            "appVersion": AppConfig.appVersion
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = await NetworkClient.perform(request: request)
    }

    private static func networkMessage(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Không thể kết nối máy chủ Key (mã mạng \(ns.code)). Hãy kiểm tra Internet rồi bấm Kích hoạt lại."
        }
        return "Dữ liệu Key từ máy chủ không hợp lệ. Hãy bấm Kích hoạt lại."
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private struct LicenseNetworkResponse {
    let manifests: [LicenseManifest]
    let source: String
}

private enum NetworkClient {
    static let sources: [(String, String)] = [
        ("GitHub Pages", "https://hieuvlog2001-creator.github.io/DSGAME/keys.json"),
        ("GitHub Raw", AppConfig.licenseURL),
        ("jsDelivr", AppConfig.licenseCDNURL)
    ]

    static func fetchLicenses() async -> Result<LicenseNetworkResponse, Error> {
        await withCheckedContinuation { continuation in
            fetchNext(index: 0, successes: [], lastError: nil, continuation: continuation)
        }
    }

    private static func fetchNext(
        index: Int,
        successes: [LicenseManifest],
        lastError: Error?,
        continuation: CheckedContinuation<Result<LicenseNetworkResponse, Error>, Never>
    ) {
        guard index < sources.count else {
            if let lastError {
                continuation.resume(returning: .failure(lastError))
            } else {
                continuation.resume(returning: .failure(URLError(.cannotLoadFromNetwork)))
            }
            return
        }

        let (name, rawURL) = sources[index]
        guard var components = URLComponents(string: rawURL) else {
            fetchNext(index: index + 1, successes: successes, lastError: URLError(.badURL), continuation: continuation)
            return
        }

        // Không dùng URLSession async/await ở đây. Completion-handler không bị SwiftUI
        // Task huỷ khi View đổi trạng thái, tránh NSURLErrorCancelled (-999).
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970 * 1000)))
        ]
        guard let url = components.url else {
            fetchNext(index: index + 1, successes: successes, lastError: URLError(.badURL), continuation: continuation)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("DSGames/1.2", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                fetchNext(index: index + 1, successes: successes, lastError: error, continuation: continuation)
                return
            }

            guard let data,
                  let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode else {
                fetchNext(index: index + 1, successes: successes, lastError: URLError(.badServerResponse), continuation: continuation)
                return
            }

            do {
                let manifest = try JSONDecoder().decode(LicenseManifest.self, from: data)
                var updated = successes
                updated.append(manifest)
                continuation.resume(returning: .success(LicenseNetworkResponse(manifests: updated, source: name)))
            } catch {
                fetchNext(index: index + 1, successes: successes, lastError: error, continuation: continuation)
            }
        }
        task.resume()
    }

    static func perform(request: URLRequest) async -> Data? {
        await withCheckedContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, _, _ in
                continuation.resume(returning: data)
            }.resume()
        }
    }
}
