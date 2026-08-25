import DataGrailConsent
import SwiftUI

// MARK: - Demo configuration
//
// Stage/tenant values are injected at launch via environment variables
// (`UC_DEMO_*`), so no api key / signer URL / customer id lives in git. Fill in
// demo-env.local.sh (copy demo-env.example.sh) and launch with the SIMCTL_CHILD_*
// forwarding shown there. Missing values fall back to loud placeholders.
//
// The Universal Consent write/read both go to `https://<consentApiHost>/universal_consent`.
enum DemoConfig {
    /// Read a launch-time env var, treating empty as unset so a blank export
    /// still surfaces the placeholder rather than silently sending "".
    private static func env(_ key: String, _ fallback: String) -> String {
        let value = ProcessInfo.processInfo.environment[key]
        return (value?.isEmpty == false) ? value! : fallback
    }

    /// Host only (no scheme). The SDK's ConsentService prepends `https://`.
    static let consentApiHost = env("UC_DEMO_CONSENT_API_HOST", "YOUR_EDGE_HOST.cloudfront.net")

    static let dgCustomerId = env("UC_DEMO_CUSTOMER_ID", "YOUR_DG_CUSTOMER_ID")
    static let apiKey = env("UC_DEMO_API_KEY", "YOUR_DEMO_API_KEY")
    static let consentProjectId = env("UC_DEMO_PROJECT_ID", "uc-demo")

    /// `getSignature` POSTs the signing payload here and expects back JSON
    /// `{ "signature": ..., "keyId": ... }`.
    static let SIGNER_URL = env("UC_DEMO_SIGNER_URL", "SIGNER_URL_TBD")

    /// GTM category keys written into the Universal Consent record.
    // Real client category keys (match consent-banner / the deployed config).
    static let analyticsKey = "dg-category-performance"
    static let marketingKey = "dg-category-marketing"

    static var isSignerConfigured: Bool {
        !SIGNER_URL.contains("SIGNER_URL_TBD")
    }
}

// MARK: - Demo consent config
//
// ConsentConfig has no public memberwise initializer and is normally fetched from a
// hosted config URL. For a self-contained demo we decode a minimal, valid config that
// points Universal Consent at the STAGE endpoint and Goofy customer. Verified to decode
// against the real `ConsentConfig` Codable.
private let demoConfigJSON = """
{
  "version": "uc-demo-v1",
  "consentContainerVersionId": "uc-demo-container",
  "dgCustomerId": "\(DemoConfig.dgCustomerId)",
  "p": 0,
  "dch": "\(DemoConfig.consentApiHost)",
  "privacyDomain": "\(DemoConfig.consentApiHost)",
  "plugins": {
    "scriptControl": false,
    "allCookieSubdomains": false,
    "cookieBlocking": false,
    "localStorageBlocking": false,
    "syncOTConsent": false
  },
  "testMode": false,
  "ignoreDoNotTrack": false,
  "trackingDetailsUrl": "https://www.datagrail.io/",
  "consentMode": "opt-in",
  "showBanner": true,
  "consentPolicy": { "name": "gdpr", "default": true },
  "gppUsNat": false,
  "initialCategories": {
    "respect_gpc": false,
    "respect_dnt": false,
    "respect_optout": false,
    "initial": [],
    "gpc": [],
    "optout": []
  },
  "layout": {
    "id": "layout-demo",
    "name": "Demo Layout",
    "status": "published",
    "default_layout": true,
    "collapsed_on_mobile": false,
    "first_layer_id": "layer-1",
    "consent_layers": {}
  },
  "consentProjectId": "\(DemoConfig.consentProjectId)",
  "universalConsent": { "enabled": true, "sync_optout": false }
}
"""

private func makeDemoConfig() throws -> ConsentConfig {
    try JSONDecoder().decode(ConsentConfig.self, from: Data(demoConfigJSON.utf8))
}

// MARK: - Universal Consent demo screen

@available(iOS 14.0, macOS 11.0, *)
struct ContentView: View {
    @State private var email = "alice@example.com"
    @State private var analyticsOn = true
    @State private var marketingOn = false

    @State private var statusText = "Ready"
    @State private var errorText: String?
    @State private var readoutText = "No read yet. Tap \"Refresh / Read\"."
    @State private var isBusy = false

    // One ConsentService instance drives the SDK's Universal Consent write/read against
    // the STAGE endpoint. privacyDomain is the host the SDK prepends with https://.
    private let consentService = ConsentService(
        networkClient: NetworkClient(),
        storage: ConsentStorage(),
        privacyDomain: DemoConfig.consentApiHost
    )

    /// SHA-256(customerId:projectId:normalizedIdentifier) — the same hash a web client
    /// computes for the same email, so a viewer can confirm both clients share a record.
    private var userHash: String {
        ConsentService.userHash(
            dgCustomerId: DemoConfig.dgCustomerId,
            consentProjectId: DemoConfig.consentProjectId,
            identifier: email
        )
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    identifierSection
                    setConsentSection
                    currentConsentSection
                    statusSection
                    footer
                }
                .padding()
            }
            .navigationTitle("Universal Consent")
        }
        .navigationViewStyle(.stack)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone")
                .font(.title2)
            Text("iOS client")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(Capsule())
            Spacer()
        }
    }

    private var identifierSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("User identifier").font(.subheadline).bold()
            TextField("email", text: $email)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled(true)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                #endif
            Text("user_hash")
                .font(.caption).foregroundColor(.secondary)
            Text(userHash)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        }
        .cardBackground()
    }

    private var setConsentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set consent").font(.subheadline).bold()
            Toggle("Analytics", isOn: $analyticsOn)
            Toggle("Marketing", isOn: $marketingOn)
            Button(action: save) {
                Text("Save")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
        }
        .cardBackground()
    }

    private var currentConsentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current consent (from server)").font(.subheadline).bold()
            Text(readoutText)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: read) {
                Text("Refresh / Read")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isBusy)
        }
        .cardBackground()
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if isBusy { ProgressView() }
                Text(statusText).font(.footnote).foregroundColor(.secondary)
            }
            if let errorText = errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Endpoint: https://\(DemoConfig.consentApiHost)/universal_consent")
            Text("customer_id: \(DemoConfig.dgCustomerId)")
            Text("project: \(DemoConfig.consentProjectId)")
            Text("signer: \(DemoConfig.SIGNER_URL)")
                .foregroundColor(DemoConfig.isSignerConfigured ? .secondary : .orange)
        }
        .font(.system(.caption2, design: .monospaced))
        .foregroundColor(.secondary)
    }

    // MARK: Actions

    /// Write the chosen preferences to the Universal Consent store via the SDK.
    /// `setUserIdentifier` writes the RAW preferences (no signal reconciliation on the
    /// write path) and signs the request by invoking `getSignature`, which calls the
    /// hosted signer. Pass `nil` for `getSignature` to send a limited (API-key-only) write.
    private func save() {
        let prefs = ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: DemoConfig.analyticsKey, isEnabled: analyticsOn),
                CategoryConsent(gtmKey: DemoConfig.marketingKey, isEnabled: marketingOn),
            ]
        )

        let config: ConsentConfig
        do {
            config = try makeDemoConfig()
        } catch {
            fail("Failed to build demo config: \(error.localizedDescription)")
            return
        }

        begin("Saving consent for \(email)…")
        consentService.setUserIdentifier(
            email,
            preferences: prefs,
            config: config,
            apiKey: DemoConfig.apiKey,
            getSignature: makeSigner()
        ) { result in
            DispatchQueue.main.async {
                self.isBusy = false
                switch result {
                case .success:
                    self.statusText = "Saved. Reading it back…"
                    self.read()
                case let .failure(error):
                    self.fail(error.errorDescription ?? "Write failed")
                }
            }
        }
    }

    /// Read the stored Universal Consent record for this identifier (unsigned GET). Shows
    /// a value written by any client — web or iOS — sharing the same user_hash.
    private func read() {
        let config: ConsentConfig
        do {
            config = try makeDemoConfig()
        } catch {
            fail("Failed to build demo config: \(error.localizedDescription)")
            return
        }

        begin("Reading consent for \(email)…")
        consentService.getUniversalConsent(
            email,
            config: config,
            apiKey: DemoConfig.apiKey
        ) { result in
            DispatchQueue.main.async {
                self.isBusy = false
                switch result {
                case let .success(record):
                    self.renderRecord(record)
                    self.statusText = "Read OK"
                    self.errorText = nil
                case let .failure(error):
                    self.fail(error.errorDescription ?? "Read failed")
                }
            }
        }
    }

    private func renderRecord(_ record: UniversalConsentRecord?) {
        guard let record = record else {
            readoutText = "No stored record for this user yet."
            return
        }
        var lines: [String] = []
        let options = record.consentPreferences?.cookieOptions ?? [:]
        // Sync the Set-consent toggles to the record we just read, so the sliders
        // reflect the stored (shared) state — otherwise a Read leaves them on their
        // local defaults and looks out of sync with "Current consent (from server)".
        analyticsOn = options[DemoConfig.analyticsKey] == true
        marketingOn = options[DemoConfig.marketingKey] == true
        for key in options.keys.sorted() {
            lines.append("\(key): \(options[key] == true ? "on" : "off")")
        }
        if lines.isEmpty { lines.append("(no categories)") }
        if let updated = record.updatedAt { lines.append("updated_at: \(updated)") }
        if let platform = record.platform { lines.append("platform: \(platform)") }
        lines.append("user_hash: \(userHash)")
        readoutText = lines.joined(separator: "\n")
    }

    /// Build the SDK's signature provider. It POSTs the SDK-minted payload
    /// `{ stringToSign, customerId, userHash, timestamp, nonce }` as JSON to `SIGNER_URL`
    /// and parses back `{ signature, keyId }`. The shared secret never touches the device.
    private func makeSigner() -> UniversalConsentSignatureProvider {
        return { payload, completion in
            guard DemoConfig.isSignerConfigured,
                  let url = URL(string: DemoConfig.SIGNER_URL), url.host != nil else {
                completion(.failure(.invalidConfiguration(
                    "SIGNER_URL is not set — replace the placeholder before running the demo"
                )))
                return
            }

            let requestBody: [String: Any] = [
                "stringToSign": payload.stringToSign,
                "customerId": payload.customerId,
                "userHash": payload.userHash,
                "timestamp": payload.timestamp,
                "nonce": payload.nonce,
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: requestBody) else {
                completion(.failure(.parseError("Could not encode signer request")))
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data

            URLSession.shared.dataTask(with: request) { data, _, error in
                if let error = error {
                    completion(.failure(.networkError(error.localizedDescription)))
                    return
                }
                guard let data = data else {
                    completion(.failure(.networkError("Empty signer response")))
                    return
                }
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let signature = object["signature"] as? String,
                      let keyId = object["keyId"] as? String else {
                    completion(.failure(.parseError("Signer response missing signature/keyId")))
                    return
                }
                completion(.success(UniversalConsentSignature(signature: signature, keyId: keyId)))
            }.resume()
        }
    }

    // MARK: Status helpers

    private func begin(_ message: String) {
        isBusy = true
        errorText = nil
        statusText = message
    }

    private func fail(_ message: String) {
        isBusy = false
        errorText = message
        statusText = "Error"
    }
}

@available(iOS 14.0, macOS 11.0, *)
private extension View {
    func cardBackground() -> some View {
        padding()
            .background(Color.gray.opacity(0.12))
            .cornerRadius(12)
    }
}
