@_spi(Diagnostics) import DataGrailConsent
import SwiftUI
import UIKit

/// Loads a pre-signed config URL from the Mobile tab and renders it with the SDK's own banner,
/// so a customer can check a test config visually before publishing it live.
struct ConfigURLTesterView: View {
    private static let loader = ConfigURLLoader()

    @State private var urlText = ""
    @State private var isLoading = false
    @State private var metadata: ConfigURLMetadata?
    @State private var loaded: LoadedConfig?
    @State private var loadError: ConfigURLLoadError?
    @State private var statusText: String?

    var body: some View {
        NavigationView {
            Form {
                urlSection
                versionSection
                resultSection
                bannerSection
            }
            .navigationTitle("Config URL Tester")
        }
        .navigationViewStyle(.stack)
    }

    private var urlSection: some View {
        Section(header: Text("Pre-signed config URL"), footer: Text("Use the Mobile tab's View config link.")) {
            TextEditor(text: $urlText)
                .font(.system(.footnote, design: .monospaced))
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .frame(minHeight: 100)
                .accessibilityIdentifier("configUrlField")
            HStack {
                Button("Paste") { urlText = UIPasteboard.general.string ?? "" }
                    .buttonStyle(.bordered)
                Spacer()
                if isLoading { ProgressView() }
                Button("Load", action: startLoad)
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                    .accessibilityIdentifier("loadButton")
            }
        }
    }

    private var versionSection: some View {
        Section(header: Text("Versions")) {
            Text("SDK library version: \(DataGrailConsent.sdkVersion)")
            Text("SDK schema version: \(DataGrailConsent.schemaVersion)")
            if let metadata = metadata {
                Text(Self.describe(metadata))
            }
        }
        .font(.footnote)
    }

    @ViewBuilder private var resultSection: some View {
        if let loadError = loadError {
            let copy = loadError.userFacing
            Section(header: Text("Error")) {
                Text(copy.title).font(.headline).foregroundColor(.red)
                Text(copy.body).font(.footnote)
            }
        } else if let loaded = loaded {
            Section(header: Text("Loaded")) {
                Text("Config version: \(loaded.config.version)")
                Text("Layers: \(loaded.config.layout.consentLayers.count)")
            }
            .font(.footnote)
        }
    }

    private var bannerSection: some View {
        Section {
            Button("Show banner") { showBanner(.modal) }
            Button("Show full screen") { showBanner(.fullScreen) }
            if let statusText = statusText {
                Text(statusText).font(.footnote).foregroundColor(.secondary)
            }
        }
        .disabled(loaded == nil)
    }

    private func startLoad() {
        guard !isLoading else { return }
        isLoading = true
        loaded = nil
        loadError = nil
        statusText = nil
        let raw = urlText
        metadata = ConfigURLLoader.validatedURL(raw).map(ConfigURLLoader.metadata(for:))
        Task { @MainActor in
            switch await Self.loader.load(raw) {
            case let .success(result): loaded = result
            case let .failure(error): loadError = error
            }
            isLoading = false
        }
    }

    private func showBanner(_ style: BannerDisplayStyle) {
        guard let config = loaded?.config else { return }
        guard let presenter = Self.presentingViewController() else {
            statusText = "A banner is already showing."
            return
        }
        let banner = BannerViewController(config: config, initialPreferences: nil, displayStyle: style) { prefs in
            if let prefs = prefs {
                let enabled = prefs.cookieOptions.filter(\.isEnabled).count
                statusText = "Banner closed: saved \(enabled) categories enabled (not persisted)"
            } else {
                statusText = "Banner closed: dismissed"
            }
        }
        presenter.present(banner, animated: true)
    }

    /// The key window's root view controller, or `nil` when it's already presenting something.
    private static func presentingViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        guard let root = root, root.presentedViewController == nil else { return nil }
        return root
    }

    private static func describe(_ metadata: ConfigURLMetadata) -> String {
        let schema = metadata.schemaVersion ?? "unversioned (legacy config.json, treated as v1)"
        var parts = ["Config schema: \(schema)", "Artifact: \(metadata.artifactMode.rawValue)"]
        if let expiresAt = metadata.expiresAt {
            let time = DateFormatter.localizedString(from: expiresAt, dateStyle: .none, timeStyle: .short)
            parts.append("Expires: \(time) (device clock)")
        }
        return parts.joined(separator: " · ")
    }
}
