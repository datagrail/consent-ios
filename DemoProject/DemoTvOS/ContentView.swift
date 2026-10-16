import SwiftUI
import DataGrailConsent

struct ContentView: View {
    @State private var isInitialized = false
    @State private var consentStatus: String = "Not initialized"
    @State private var categories: [String: Bool] = [:]
    @State private var showingBanner = false
    @Namespace private var buttonsNamespace

    // ───────────────────────────────────────────────────────────────────────
    // HTTPS host that proxies to the local test server (root → localhost:8080).
    // HTTPS lets the stock iOS Camera app open the QR link and avoids ATS issues.
    private let serverBase = "https://bradleyy.dg-dev.com"
    // ───────────────────────────────────────────────────────────────────────

    // SDK initializes from a FULL ConsentConfig (with layout) so the banner renders.
    private var configUrl: String { "\(serverBase)/tv/demo-config.json" }
    // The phone's QR page only needs category toggles (sample-config is fine).
    private var phoneConfigUrl: String { "\(serverBase)/tv/sample-config.json" }
    // The TV polls this base for consent reads (full scheme+host+port).
    private var apiBaseUrl: String { serverBase }
    private let customerId = "cust-1"
    private let apiKey = "dg_test_readkey"  // matches the test server's default API_KEYS

    var body: some View {
        VStack(spacing: 40) {
            Text("DataGrail Consent SDK")
                .font(.system(size: 48, weight: .bold))

            Text("tvOS QR Pairing Demo")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Divider()

            VStack(spacing: 24) {
                InfoRow(label: "Status", value: consentStatus)
                InfoRow(label: "Server", value: serverBase)
                InfoRow(label: "SDK config", value: configUrl)
            }
            .padding()
            .background(Color.secondary.opacity(0.2))
            .cornerRadius(12)

            if !categories.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Category Status")
                        .font(.system(size: 32, weight: .semibold))

                    ForEach(Array(categories.keys.sorted()), id: \.self) { key in
                        HStack {
                            Text(key)
                                .font(.system(size: 24))
                            Spacer()
                            Text(categories[key] == true ? "✅ Enabled" : "❌ Disabled")
                                .font(.system(size: 24))
                                .foregroundColor(categories[key] == true ? .green : .red)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(12)
            }

            HStack(spacing: 40) {
                // NOTE: no .disabled() on these buttons. On tvOS, disabling the
                // currently-focused button (e.g. Initialize after it runs) orphans
                // focus and the remote stops responding. Buttons stay enabled and
                // guard their own preconditions internally instead.
                // Use the system default tvOS button style — it is fully
                // focus-engine aware (visible highlight/lift, reliable Select).
                // The previous custom ButtonStyle only reacted to isPressed, not
                // focus, so nothing highlighted and the screen felt unresponsive.
                Button("Initialize") {
                    initializeSDK()
                }
                .prefersDefaultFocus(in: buttonsNamespace)

                Button("Show Banner (D-pad only)") {
                    showBannerDPad()
                }

                Button("Show Banner + QR Pairing") {
                    showBannerWithQR()
                }

                Button("Reset") {
                    reset()
                }
            }
            .focusScope(buttonsNamespace)

            Spacer()

            Text("Instructions:")
                .font(.system(size: 28, weight: .semibold))
            Text("1. Start the test server on your Mac, exposed at \(serverBase)")
                .font(.system(size: 22))
            Text("2. Initialize → Show Banner + QR")
                .font(.system(size: 22))
            Text("3. Scan the QR with your phone → toggle + Save → watch this update")
                .font(.system(size: 22))
        }
        .padding(60)
        .onAppear {
            updateCategoryStatus()
        }
    }

    private func initializeSDK() {
        guard let url = URL(string: configUrl) else {
            consentStatus = "Invalid config URL"
            return
        }

        DataGrailConsent.shared.initialize(
            configUrl: url,
            apiKey: apiKey
        ) { result in
            switch result {
            case .success:
                isInitialized = true
                consentStatus = "Initialized"
                updateCategoryStatus()
            case let .failure(error):
                consentStatus = "Error: \(error.localizedDescription)"
            }
        }
    }

    private func showBannerDPad() {
        guard isInitialized else { consentStatus = "Tap Initialize first"; return }
        // D-pad only banner (no QR pairing)
        guard let rootVC = UIApplication.shared.windows.first?.rootViewController else {
            return
        }

        DataGrailConsent.shared.showBanner(from: rootVC) { preferences in
            if preferences != nil {
                consentStatus = "Consent saved"
                updateCategoryStatus()
            } else {
                consentStatus = "Banner dismissed"
            }
        }
    }

    private func showBannerWithQR() {
        guard isInitialized else { consentStatus = "Tap Initialize first"; return }
        // Banner with QR pairing
        guard let rootVC = UIApplication.shared.windows.first?.rootViewController else {
            return
        }

        DataGrailConsent.shared.showBannerWithQRPairing(
            from: rootVC,
            publicBaseUrl: serverBase,
            configUrl: phoneConfigUrl,
            customerId: customerId,
            apiBaseUrl: apiBaseUrl
        ) { preferences in
            if preferences != nil {
                consentStatus = "Consent saved (QR pairing or manual)"
                updateCategoryStatus()
            } else {
                consentStatus = "Banner dismissed or timeout"
            }
        }
    }

    private func reset() {
        DataGrailConsent.shared.reset()
        isInitialized = false
        consentStatus = "Reset"
        categories = [:]
    }

    private func updateCategoryStatus() {
        guard isInitialized else { return }

        // Get all categories
        if let prefs = try? DataGrailConsent.shared.getCategories() {
            var newCategories: [String: Bool] = [:]
            for categoryConsent in prefs.cookieOptions {
                newCategories[categoryConsent.gtmKey] = categoryConsent.isEnabled
            }
            categories = newCategories
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 24))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

#Preview {
    ContentView()
}
