import SwiftUI
import DataGrailConsent

struct ContentView: View {
    @State private var isInitialized = false
    @State private var consentStatus: String = "Not initialized"
    @State private var categories: [String: Bool] = [:]
    @State private var showingBanner = false

    // Test server settings (adjust for your LAN or tunnel)
    private let publicBaseUrl = "http://192.168.1.5:8080"  // Change to your Mac's LAN IP
    private let configUrl = "http://192.168.1.5:8080/tv/sample-config.json"
    private let customerId = "cust-1"

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
                InfoRow(label: "Config URL", value: configUrl)
                InfoRow(label: "Public Base URL", value: publicBaseUrl)
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
                Button("Initialize") {
                    initializeSDK()
                }
                .buttonStyle(.card)
                .disabled(isInitialized)

                Button("Show Banner (D-pad only)") {
                    showBannerDPad()
                }
                .buttonStyle(.card)
                .disabled(!isInitialized)

                Button("Show Banner + QR Pairing") {
                    showBannerWithQR()
                }
                .buttonStyle(.card)
                .disabled(!isInitialized)

                Button("Reset") {
                    reset()
                }
                .buttonStyle(.card)
            }

            Spacer()

            Text("Instructions:")
                .font(.system(size: 28, weight: .semibold))
            Text("1. Start the test server on your Mac (see README)")
                .font(.system(size: 22))
            Text("2. Update publicBaseUrl above to your Mac's LAN IP")
                .font(.system(size: 22))
            Text("3. Initialize → Show Banner + QR → Scan with phone")
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
            apiKey: "test-api-key"  // For local dev with test server
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
        // Banner with QR pairing
        guard let rootVC = UIApplication.shared.windows.first?.rootViewController else {
            return
        }

        DataGrailConsent.shared.showBannerWithQRPairing(
            from: rootVC,
            publicBaseUrl: publicBaseUrl,
            configUrl: configUrl,
            customerId: customerId
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

struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 28, weight: .semibold))
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
            .background(
                configuration.isPressed
                    ? Color.blue.opacity(0.8)
                    : Color.blue
            )
            .foregroundColor(.white)
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CardButtonStyle {
    static var card: CardButtonStyle {
        CardButtonStyle()
    }
}

#Preview {
    ContentView()
}
