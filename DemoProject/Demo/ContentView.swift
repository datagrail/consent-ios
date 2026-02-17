import DataGrailConsent
import SwiftUI

// swiftlint:disable type_body_length
@available(iOS 14.0, macOS 11.0, *)
struct ContentView: View {
    @State private var configUrlText =
        "https://api.consentjs.datagrailstaging.com/consent/ac46d8ad-a67a-431f-a5d5-9e3eb922dae7/b17d1e73-6d35-4ae3-9199-ff2e98d8926a/config.json"
    @State private var statusText = "Not initialized"
    @State private var isInitialized = false
    @State private var preferences: ConsentPreferences?
    @State private var config: ConsentConfig?
    @State private var logMessages: [LogMessage] = []

    struct LogMessage: Identifiable {
        let id = UUID()
        let level: String
        let message: String
        let timestamp: Date

        var levelColor: Color {
            switch level {
            case "ERROR": return .red
            case "WARNING": return .orange
            case "SUCCESS": return .green
            case "DEBUG": return .gray
            case "NETWORK": return .blue
            default: return .primary
            }
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Config URL Section
                    GroupBox(label: Label("Config URL", systemImage: "link")) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Enter config URL", text: $configUrlText)
                                .font(.system(.caption, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            Text("Enter the full URL to your config.json")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 8)
                    }

                    // Status Section
                    GroupBox(label: Label("Status", systemImage: "info.circle")) {
                        Text(statusText)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }

                    // Actions Section
                    GroupBox(label: Label("Actions", systemImage: "hand.tap")) {
                        VStack(spacing: 12) {
                            Button(action: initializeSDK) {
                                Label("Initialize SDK", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            HStack(spacing: 12) {
                                Button {
                                    showBanner(style: .modal)
                                } label: {
                                    Label("Modal Banner", systemImage: "rectangle.portrait")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!isInitialized)

                                Button {
                                    showBanner(style: .fullScreen)
                                } label: {
                                    Label("Full Screen", systemImage: "rectangle.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)
                                .disabled(!isInitialized)
                            }

                            Button(action: resetSDK) {
                                Label("Reset", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        }
                        .padding(.vertical, 8)
                    }

                    // Policy Section
                    if let config {
                        GroupBox(label: Label("Policy Information", systemImage: "doc.text")) {
                            VStack(alignment: .leading, spacing: 8) {
                                policyRow(label: "Policy Name:", value: config.consentPolicy.name)
                                policyRow(
                                    label: "Default Policy:",
                                    value: config.consentPolicy.default ? "Yes" : "No",
                                    color: config.consentPolicy.default ? .green : .orange
                                )
                                policyRow(
                                    label: "Show Banner:",
                                    value: config.showBanner ? "Yes" : "No",
                                    color: config.showBanner ? .green : .orange
                                )
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                        }
                    }

                    // Current Preferences Section
                    if let preferences {
                        GroupBox(label: Label("Current Preferences", systemImage: "list.bullet")) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Customised: \(preferences.isCustomised ? "Yes" : "No")")
                                Text("Categories: \(preferences.cookieOptions.count)")
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                        }
                    }

                    // Category Status Section
                    if let preferences, !preferences.cookieOptions.isEmpty {
                        GroupBox(label: Label("Category Status", systemImage: "checklist")) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(preferences.cookieOptions, id: \.gtmKey) { category in
                                    HStack {
                                        Image(
                                            systemName: category.isEnabled
                                                ? "checkmark.circle.fill" : "xmark.circle.fill"
                                        )
                                        .foregroundColor(category.isEnabled ? .green : .red)
                                        Text(category.gtmKey)
                                            .font(.system(.caption, design: .monospaced))
                                        Spacer()
                                        Text(category.isEnabled ? "Enabled" : "Disabled")
                                            .font(.caption2)
                                            .foregroundColor(category.isEnabled ? .green : .red)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                        }
                    }

                    // Debug Log Section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 0) {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 2) {
                                        ForEach(logMessages) { log in
                                            HStack(alignment: .top, spacing: 4) {
                                                Text("[\(log.level)]")
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundColor(log.levelColor)
                                                    .frame(width: 70, alignment: .leading)
                                                Text(log.message)
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                            }
                                            .id(log.id)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(height: 150)
                                .onChange(of: logMessages.count) { _ in
                                    if let lastMessage = logMessages.last {
                                        withAnimation {
                                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                        }
                                    }
                                }
                            }

                            Divider()
                                .padding(.vertical, 4)

                            HStack {
                                Button(action: clearLogs) {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)

                                Button(action: copyLogs) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)

                                Spacer()

                                Text("\(logMessages.count) entries")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } label: {
                        Label("Debug Log", systemImage: "terminal")
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("DataGrail Consent")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func policyRow(
        label: String, value: String, color: Color = .secondary
    ) -> some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .foregroundColor(color)
        }
    }

    // MARK: - Actions

    private func logConfigInfo(_ config: ConsentConfig) {
        log("INFO", "Config loaded:")
        log(
            config.showBanner ? "INFO" : "WARNING",
            "  showBanner = \(config.showBanner)"
        )
        log("DEBUG", "  version = \(config.version)")
        log("DEBUG", "  layers = \(config.layout.consentLayers.count)")

        if !config.showBanner {
            log(
                "WARNING",
                "showBanner=false - shouldDisplayBanner() will return false"
            )
            log("INFO", "But banner buttons will still work for testing")
        }
    }

    private func logStateAfterInit() {
        let shouldDisplay =
            (try? DataGrailConsent.shared.shouldDisplayBanner()) ?? false
        let hasConsent = (try? DataGrailConsent.shared.hasUserConsent()) ?? false
        log("DEBUG", "shouldDisplayBanner() = \(shouldDisplay)")
        log("DEBUG", "hasUserConsent() = \(hasConsent)")

        if let prefs = try? DataGrailConsent.shared.getUserPreferences() {
            log(
                "DEBUG",
                "getUserPreferences() returned \(prefs.cookieOptions.count) categories"
            )
            prefs.cookieOptions.forEach { opt in
                log(
                    "DEBUG",
                    "  - \(opt.gtmKey): \(opt.isEnabled ? "enabled" : "disabled")"
                )
            }
        } else {
            log("DEBUG", "getUserPreferences() returned nil")
        }
    }

    private func initializeSDK() {
        statusText = "Initializing SDK..."
        log("INFO", "Initializing SDK...")

        guard
            let configUrl = URL(string: configUrlText.trimmingCharacters(in: .whitespaces))
        else {
            statusText = "❌ Invalid config URL"
            log("ERROR", "Invalid config URL")
            return
        }

        log("NETWORK", "Fetching config from: \(configUrl.host ?? "unknown")")

        DataGrailConsent.shared.initialize(configUrl: configUrl) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    log("SUCCESS", "Initialize returned SUCCESS")
                    statusText = "✅ SDK initialized"
                    isInitialized = true
                    config = DataGrailConsent.shared.getConfig()

                    if let config {
                        logConfigInfo(config)
                    }

                    logStateAfterInit()
                    checkStatus()
                case let .failure(error):
                    log("ERROR", "Initialize returned FAILURE")
                    log("ERROR", "Error: \(error.localizedDescription)")
                    statusText = "❌ Init failed: \(error)"
                    isInitialized = false
                }
            }
        }
    }

    private func showBanner(style: BannerDisplayStyle) {
        log("INFO", "Show banner requested (style: \(style))")

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController
        else {
            statusText = "❌ No view controller"
            log("ERROR", "No view controller available")
            return
        }

        // Log config details before showing banner
        if let config {
            log("DEBUG", "Config firstLayerId: \(config.layout.firstLayerId)")
            log(
                "DEBUG",
                "Config consentLayers keys: \(config.layout.consentLayers.keys.joined(separator: ", "))"
            )
            if let firstLayer = config.layout.consentLayers[config.layout.firstLayerId] {
                log("DEBUG", "First layer has \(firstLayer.elements.count) elements")
            } else {
                log("ERROR", "First layer NOT FOUND!")
            }
        }

        log("NETWORK", "Calling showBanner(style: \(style))...")

        DataGrailConsent.shared.showBanner(from: rootViewController, style: style) { [self] prefs in
            DispatchQueue.main.async {
                if let prefs {
                    log("SUCCESS", "Banner completed with preferences")
                    log("DEBUG", "Categories: \(prefs.cookieOptions.count)")
                    statusText = "✅ Preferences saved"
                    preferences = prefs
                } else {
                    log("WARNING", "Banner dismissed without saving")
                    statusText = "⚠️ Banner dismissed"
                }
                checkStatus()
            }
        }
    }

    private func checkStatus() {
        log("DEBUG", "Checking status...")

        let shouldDisplay = (try? DataGrailConsent.shared.shouldDisplayBanner()) ?? false

        do {
            preferences = try DataGrailConsent.shared.getCategories()
            log(
                "DEBUG",
                "getCategories() returned \(preferences?.cookieOptions.count ?? 0) categories"
            )
            preferences?.cookieOptions.forEach { opt in
                log("DEBUG", "  - \(opt.gtmKey): \(opt.isEnabled ? "enabled" : "disabled")")
            }
        } catch {
            log("ERROR", "getCategories() threw: \(error)")
            preferences = nil
        }

        log("DEBUG", "shouldDisplayBanner = \(shouldDisplay)")
        log("DEBUG", "preferences = \(preferences != nil ? "present" : "nil")")

        if !isInitialized {
            statusText = "🔄 Not initialized"
        } else if shouldDisplay {
            statusText = "⚠️ Consent required"
        } else if let prefs = preferences {
            statusText = "✅ Consent: \(prefs.cookieOptions.count) categories"
        } else {
            statusText = "✅ Initialized (no preferences yet)"
        }
    }

    private func resetSDK() {
        log("INFO", "Reset SDK requested")
        DataGrailConsent.shared.reset()
        log("SUCCESS", "SDK reset complete")
        statusText = "🔄 SDK reset - reinitialize"
        isInitialized = false
        preferences = nil
        config = nil
    }

    // MARK: - Logging

    private func log(_ level: String, _ message: String) {
        logMessages.append(LogMessage(level: level, message: message, timestamp: Date()))
    }

    private func clearLogs() {
        logMessages.removeAll()
    }

    private func copyLogs() {
        let logText = logMessages.map { "[\($0.level)] \($0.message)" }.joined(separator: "\n")
        UIPasteboard.general.string = logText
    }
}

#Preview {
    ContentView()
}
