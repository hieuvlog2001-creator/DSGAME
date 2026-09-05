import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var licenseStore: LicenseStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch licenseStore.state {
            case .checking:
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.2)
                    Text("Đang kiểm tra Key…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.965, green: 0.972, blue: 0.99))
            case .locked(let message):
                ActivationView(message: message)
            case .active:
                ContentView()
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .active {
                await licenseStore.refresh()
                await licenseStore.syncDeviceStatus()
            }
        }
    }
}

struct ActivationView: View {
    @EnvironmentObject private var licenseStore: LicenseStore
    let message: String?
    @State private var key = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 55)
                ZStack {
                    Circle().fill(Color.blue.opacity(0.12)).frame(width: 94, height: 94)
                    Image(systemName: "key.fill").font(.system(size: 42)).foregroundStyle(.blue)
                }
                VStack(spacing: 7) {
                    Text("DSGames").font(.system(size: 32, weight: .bold))
                    Text("Kích hoạt Key để tiếp tục").font(.system(size: 17)).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("Thông tin thiết bị", systemImage: "iphone")
                        .font(.headline)
                    HStack { Text("Thiết bị"); Spacer(); Text(DeviceInfo.modelName).fontWeight(.semibold) }
                    HStack { Text("Phiên bản iOS"); Spacer(); Text("iOS \(DeviceInfo.iosVersion)").fontWeight(.semibold) }
                    HStack { Text("DSGames"); Spacer(); Text("v\(AppConfig.appVersion)").fontWeight(.semibold) }
                }
                .padding(18)
                .background(.white.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Key kích hoạt").font(.headline)
                    TextField("DSG-XXXX-XXXX-XXXX", text: $key)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.18)))
                    if let message, !message.isEmpty {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                    Button {
                        Task { await licenseStore.activate(key: key) }
                    } label: {
                        HStack {
                            if licenseStore.isSubmitting { ProgressView().tint(.white) }
                            Text(licenseStore.isSubmitting ? "Đang kiểm tra…" : "Kích hoạt")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || licenseStore.isSubmitting)

                    Button {
                        Task { await licenseStore.refresh() }
                    } label: {
                        Label("Cập nhật Key mới", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(licenseStore.isSubmitting)

                    Text("Key được kiểm tra trực tiếp từ máy chủ. Nếu Admin vừa tạo Key mới, chỉ cần nhập Key mới rồi bấm Kích hoạt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !licenseStore.serverSource.isEmpty {
                        Text("Nguồn máy chủ: \(licenseStore.serverSource)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .background(.white.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 22))
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
        .background(Color(red: 0.965, green: 0.972, blue: 0.99).ignoresSafeArea())
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var licenseStore: LicenseStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var selectedGame: Game?
    @State private var showingDeviceInfo = false

    var body: some View {
        TabView(selection: $selectedTab) {
            GamesView(selectedGame: $selectedGame)
                .tabItem { Label("Games", systemImage: "scope") }
                .tag(0)
            AppsPlaceholderView()
                .tabItem { Label("Ứng dụng", systemImage: "square.grid.2x2.fill") }
                .tag(1)
        }
        .tint(Color(red: 0.05, green: 0.49, blue: 0.92))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await store.refresh()
                await licenseStore.refresh()
                await licenseStore.syncDeviceStatus()
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .active {
                await store.refresh()
                await licenseStore.refresh()
                await licenseStore.syncDeviceStatus()
            }
        }
        .sheet(isPresented: $showingDeviceInfo) {
            DeviceInfoSheet(licenseStore: licenseStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await store.refresh(); await licenseStore.refresh() }
                    } label: { Label("Làm mới danh sách", systemImage: "arrow.clockwise") }
                    Button {
                        showingDeviceInfo = true
                    } label: { Label("Thông tin thiết bị", systemImage: "iphone") }
                    Divider()
                    Button(role: .destructive) {
                        licenseStore.logout()
                    } label: { Label("Đổi Key", systemImage: "key.fill") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.blue)
                        .frame(width: 42, height: 42)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Menu DSGames")
            }
        }
    }
}

struct DeviceInfoSheet: View {
    let licenseStore: LicenseStore
    var body: some View {
        NavigationStack {
            List {
                Section("DSGames") {
                    LabeledContent("Phiên bản app", value: "v\(AppConfig.appVersion)")
                    LabeledContent("Key", value: licenseStore.keyPreview)
                    LabeledContent("Hạn dùng", value: licenseStore.remainingText())
                }
                Section("Thiết bị") {
                    LabeledContent("Tên thiết bị", value: DeviceInfo.modelName)
                    LabeledContent("Model", value: DeviceInfo.modelIdentifier)
                    LabeledContent("Phiên bản iOS", value: "iOS \(DeviceInfo.iosVersion)")
                    LabeledContent("Device ID", value: DeviceInfo.vendorIdentifier)
                    LabeledContent("IMEI", value: DeviceInfo.imeiDisplay)
                }
            }
            .navigationTitle("Thông tin thiết bị")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct GamesView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var licenseStore: LicenseStore
    @Binding var selectedGame: Game?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    statusCard
                    Text("Chọn game")
                        .font(.system(size: 32, weight: .bold))
                        .padding(.top, 28)
                    Text("Chạm Cài đặt để tải IPA hoặc Mở để quay lại game đã cài.")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .padding(.top, 5)
                        .padding(.bottom, 26)

                    LazyVStack(spacing: 14) {
                        ForEach(store.games) { game in
                            GameCard(game: game) { selectedGame = game }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
            }
            .background(Color(red: 0.965, green: 0.972, blue: 0.99).ignoresSafeArea())
            .sheet(item: $selectedGame) { game in
                GameInfoSheet(game: game)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("DSGames").font(.system(size: 26, weight: .bold))
                Text("v\(AppConfig.appVersion) · \(DeviceInfo.modelName) · iOS \(DeviceInfo.iosVersion)")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Text("🇻🇳")
                Text("VI").fontWeight(.semibold)
                Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(.white.opacity(0.88))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.gray.opacity(0.14)))
            .clipShape(Capsule())
        }
        .padding(.top, 8)
    }

    private var statusCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(Color.green.opacity(0.14)).frame(width: 64, height: 64)
                    Image(systemName: "checkmark.shield.fill").font(.system(size: 31)).foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sẵn sàng").font(.system(size: 19, weight: .bold))
                    Text(licenseStore.remainingText(at: context.date))
                        .font(.system(size: 16)).foregroundStyle(.secondary)
                    if store.isLoading {
                        Text("Đang đồng bộ danh sách game…")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Text("Thiết bị: \(DeviceInfo.modelName) · iOS \(DeviceInfo.iosVersion)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Circle().fill(.green).frame(width: 14, height: 14)
            }
            .padding(22)
            .background(.white.opacity(0.45))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.green.opacity(0.2), lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .padding(.top, 34)
        }
    }

}

struct GameCard: View {
    let game: Game
    let action: () -> Void
    @EnvironmentObject private var store: GameStore
    @Environment(\.openURL) private var openURL
    @State private var showingInstallInfo = false

    var tint: Color {
        switch game.color.lowercased() {
        case "orange": return .orange
        case "red": return .red
        case "yellow": return .yellow
        case "green": return .green
        default: return .cyan
        }
    }

    private var installURL: URL? {
        guard let m = game.manifestURL, !m.isEmpty else { return nil }
        return URL(string: "itms-services://?action=download-manifest&url=\(m.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? m)")
    }

    private var installedVersion: String? { store.installedVersion(for: game) }
    private var hasNewVersion: Bool {
        guard let installedVersion, !installedVersion.isEmpty, let serverVersion = game.version else { return false }
        return installedVersion != serverVersion
    }

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: URL(string: game.iconURL ?? "")) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { Image(systemName: "square.grid.3x3").font(.system(size: 32)).foregroundStyle(.gray.opacity(0.55)) }
            }
            .frame(width: 76, height: 76).background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(.gray.opacity(0.12)))

            VStack(alignment: .leading, spacing: 6) {
                Button(action: action) {
                    Text(game.name).font(.system(size: 19, weight: .semibold)).foregroundStyle(.primary)
                }
                HStack(spacing: 8) {
                    Circle().fill(tint).frame(width: 10, height: 10)
                    Text(statusText).font(.system(size: 15, weight: .medium)).foregroundStyle(statusColor)
                        .lineLimit(1)
                }
                if let v = game.version, !v.isEmpty {
                    Text(hasNewVersion ? "Mới: v\(v)" : "v\(v)")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 9) {
                if hasNewVersion, let url = installURL {
                    Button {
                        store.markInstallRequested(for: game)
                        openURL(url)
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 25)).foregroundStyle(tint.opacity(0.9))
                    }
                    .accessibilityLabel("Cập nhật \(game.name)")
                } else if installedVersion == nil, let url = installURL {
                    Button {
                        store.markInstallRequested(for: game)
                        openURL(url)
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 25)).foregroundStyle(tint.opacity(0.9))
                    }
                    .accessibilityLabel("Cài đặt \(game.name)")
                }

                if game.launchURL != nil, !(game.launchURL ?? "").isEmpty {
                    Button {
                        store.openGame(game) { success in
                            if !success { showingInstallInfo = true }
                        }
                    } label: {
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.system(size: 23)).foregroundStyle(tint.opacity(0.85))
                    }
                    .accessibilityLabel("Mở \(game.name)")
                }

                Button(action: action) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 23)).foregroundStyle(tint.opacity(0.8))
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.42))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(tint.opacity(0.16), lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .alert("Không mở được game", isPresented: $showingInstallInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Hãy cài IPA trước và kiểm tra Launch URL / Deep Link của game trong Admin.")
        }
    }

    private var statusText: String {
        if hasNewVersion { return "Có bản cập nhật" }
        if installedVersion != nil { return "Đã cài / Sẵn sàng mở" }
        return "Chưa cài"
    }

    private var statusColor: Color {
        if hasNewVersion { return .orange }
        if installedVersion != nil { return .green }
        return .secondary
    }
}

struct GameInfoSheet: View {
    let game: Game
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var openFailed = false

    private var installURL: URL? {
        guard let m = game.manifestURL, !m.isEmpty else { return nil }
        return URL(string: "itms-services://?action=download-manifest&url=\(m.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? m)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(game.name).font(.system(size: 27, weight: .bold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }
            }
            if let v = game.version, !v.isEmpty { Text("Phiên bản trên server: \(v)").font(.subheadline.weight(.semibold)) }
            if let local = store.installedVersion(for: game), !local.isEmpty {
                Text("Phiên bản đã yêu cầu cài: \(local)").font(.subheadline).foregroundStyle(.green)
            }
            Text(game.info ?? "Chưa có thông tin cho game này.").font(.system(size: 17)).foregroundStyle(.secondary)
            HStack {
                if let url = installURL {
                    Button("Cài đặt / Cập nhật") {
                        store.markInstallRequested(for: game)
                        openURL(url)
                    }.buttonStyle(.borderedProminent)
                }
                if let raw = game.launchURL, !raw.isEmpty {
                    Button("Mở game") {
                        store.openGame(game) { success in
                            if !success { openFailed = true }
                        }
                    }.buttonStyle(.bordered)
                }
            }
            Text("Sau khi iOS cài xong, nút Mở game sẽ gọi Deep Link của game. DSGames không thể chạy file IPA bên trong chính nó; IPA phải được cài thành một ứng dụng riêng trên iOS.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .alert("Không mở được", isPresented: $openFailed) { Button("OK", role: .cancel) {} }
            message: { Text("Kiểm tra Launch URL / Deep Link của game trong trang Admin.") }
    }
}

struct AppsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Image(systemName: "square.grid.2x2.fill").font(.system(size: 50)).foregroundStyle(.blue)
                Text("Ứng dụng").font(.title.bold())
                Text("Bạn có thể mở rộng mục này thành kho ứng dụng riêng.").foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(30)
        }
    }
}
