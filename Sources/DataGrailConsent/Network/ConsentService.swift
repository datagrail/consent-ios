import CryptoKit
import Foundation

/// Signature material returned by the customer-provided `getSignature` closure.
///
/// The SDK never holds the HMAC secret and never computes the signature itself.
/// The customer's backend computes `HMAC-SHA256(secret, customerId:userHash:timestamp)`
/// and hands back this value; the SDK only attaches it as request headers.
public struct UniversalConsentSignature {
    /// Hex HMAC signature computed by the customer backend.
    public let signature: String
    /// Identifies which HMAC secret was used (supports key rotation).
    public let keyId: String
    /// Unix timestamp (seconds) the signature was minted for.
    public let timestamp: Int64

    public init(signature: String, keyId: String, timestamp: Int64) {
        self.signature = signature
        self.keyId = keyId
        self.timestamp = timestamp
    }
}

/// Customer-provided callback that vouches for the current user by returning
/// signature material. Result-based to match this SDK's existing callback style.
/// The SDK invokes it per write attempt so an expired signature can be re-minted.
public typealias UniversalConsentSignatureProvider =
    (@escaping (Result<UniversalConsentSignature, ConsentError>) -> Void) -> Void

/// Service for sending consent data to backend
public class ConsentService {
    private let networkClient: NetworkClient
    private let storage: ConsentStorage
    private let privacyDomain: String

    public init(
        networkClient: NetworkClient,
        storage: ConsentStorage,
        privacyDomain: String
    ) {
        self.networkClient = networkClient
        self.storage = storage
        self.privacyDomain = privacyDomain
    }

    /// Save consent preferences to backend
    /// - Parameters:
    ///   - preferences: The consent preferences to save
    ///   - config: The consent configuration
    ///   - completion: Completion handler with result
    public func savePreferences(
        preferences: ConsentPreferences,
        config: ConsentConfig,
        completion: @escaping (Result<Void, ConsentError>) -> Void
    ) {
        let url = buildURL(path: "/save_preferences")

        var payload: [String: Any] = [
            "dg_customer_id": config.dgCustomerId,
            "consent_id": storage.getOrCreateUniqueId(),
            "config_version": config.version,
            "consent_container_version_id": config.consentContainerVersionId,
            "policyName": config.consentPolicy.name,
            "is_customised": preferences.isCustomised,
            "cookie_options": preferences.cookieOptions.map { option in
                [
                    "gtm_key": option.gtmKey,
                    "is_enabled": option.isEnabled,
                ]
            },
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        if let policyUuid = config.consentPolicy.uuid {
            payload["policyUuid"] = policyUuid
        }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(.failure(.parseError("Failed to encode preferences payload")))
            return
        }

        networkClient.retryWithBackoff(
            operation: { operationCompletion in
                self.networkClient.request(
                    url: url,
                    method: .post,
                    body: body,
                    completion: { result in
                        switch result {
                        case .success:
                            operationCompletion(.success(()))
                        case let .failure(error):
                            operationCompletion(.failure(error))
                        }
                    }
                )
            },
            completion: { result in
                switch result {
                case .success:
                    completion(.success(()))
                case let .failure(error):
                    // Queue for retry if network failed
                    self.queueFailedRequest(payload: payload, endpoint: "save_preferences")
                    completion(.failure(error))
                }
            }
        )
    }

    private var currentLocaleCode: String {
        if #available(iOS 16, macOS 13, *) {
            return Locale.current.language.languageCode?.identifier ?? "en"
        } else {
            return Locale.current.languageCode ?? "en"
        }
    }

    /// Save banner open event to backend
    /// - Parameters:
    ///   - config: The consent configuration
    ///   - completion: Completion handler with result
    public func saveOpen(
        config: ConsentConfig,
        completion: @escaping (Result<Void, ConsentError>) -> Void
    ) {
        let consentId = storage.getOrCreateUniqueId()
        let localeCode = currentLocaleCode
        let timestamp = ISO8601DateFormatter().string(from: Date())

        var components = URLComponents(string: "https://\(privacyDomain)/save_open")
        var queryItems = [
            URLQueryItem(name: "customer", value: config.dgCustomerId),
            URLQueryItem(name: "action", value: "open"),
            URLQueryItem(name: "policy_name", value: config.consentPolicy.name),
            URLQueryItem(name: "revision", value: config.version),
            URLQueryItem(name: "default_policy", value: String(config.consentPolicy.default)),
            URLQueryItem(name: "locale_code", value: localeCode),
            URLQueryItem(name: "consent_id", value: consentId),
            URLQueryItem(name: "config_version", value: config.version),
            URLQueryItem(name: "consent_container_version_id", value: config.consentContainerVersionId),
            URLQueryItem(name: "timestamp", value: timestamp),
        ]
        if let policyUuid = config.consentPolicy.uuid {
            queryItems.append(URLQueryItem(name: "policy_uuid", value: policyUuid))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            completion(.failure(.networkError("Invalid URL")))
            return
        }

        networkClient.retryWithBackoff(
            operation: { operationCompletion in
                self.networkClient.request(url: url, method: .get) { result in
                    switch result {
                    case .success: operationCompletion(.success(()))
                    case let .failure(error): operationCompletion(.failure(error))
                    }
                }
            },
            completion: { result in
                switch result {
                case .success:
                    completion(.success(()))
                case let .failure(error):
                    var payload: [String: Any] = [
                        "customer": config.dgCustomerId,
                        "action": "open",
                        "policy_name": config.consentPolicy.name,
                        "revision": config.version,
                        "default_policy": String(config.consentPolicy.default),
                        "locale_code": localeCode,
                        "consent_id": consentId,
                        "config_version": config.version,
                        "consent_container_version_id": config.consentContainerVersionId,
                        "timestamp": timestamp,
                    ]
                    if let policyUuid = config.consentPolicy.uuid {
                        payload["policy_uuid"] = policyUuid
                    }
                    self.queueFailedRequest(payload: payload, endpoint: "save_open")
                    completion(.failure(error))
                }
            }
        )
    }

    /// Retry any pending requests that failed previously
    /// - Parameter completion: Completion handler called when all retries complete
    public func retryPendingRequests(completion: @escaping (Int, Int) -> Void) {
        let events = storage.loadPendingEvents()
        guard !events.isEmpty else {
            completion(0, 0)
            return
        }

        var successCount = 0
        var failureCount = 0
        let group = DispatchGroup()

        for event in events {
            guard let endpoint = event["endpoint"] as? String,
                  let payload = event["payload"] as? [String: Any]
            else {
                continue
            }

            group.enter()

            if endpoint == "save_preferences" {
                let url = buildURL(path: "/save_preferences")
                guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
                    failureCount += 1
                    group.leave()
                    continue
                }

                networkClient.request(url: url, method: .post, body: body) { result in
                    if case .success = result {
                        successCount += 1
                    } else {
                        failureCount += 1
                    }
                    group.leave()
                }
            } else if endpoint == "save_open" {
                var components = URLComponents(string: "https://\(privacyDomain)/save_open")
                components?.queryItems = payload.map { key, value in
                    let name = key == "dg_customer_id" ? "customer" : key
                    return URLQueryItem(name: name, value: "\(value)")
                }

                guard let url = components?.url else {
                    failureCount += 1
                    group.leave()
                    continue
                }

                networkClient.request(url: url, method: .get) { result in
                    if case .success = result {
                        successCount += 1
                    } else {
                        failureCount += 1
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            // Remove successful events from queue
            if successCount > 0 {
                let remainingEvents = Array(events.suffix(failureCount))
                try? self.storage.savePendingEvents(remainingEvents)
            }
            completion(successCount, failureCount)
        }
    }

    // MARK: - Private Methods

    private func buildURL(path: String) -> URL {
        guard let url = URL(string: "https://\(privacyDomain)\(path)") else {
            preconditionFailure("Invalid URL: https://\(privacyDomain)\(path)")
        }
        return url
    }

    private func queueFailedRequest(payload: [String: Any], endpoint: String) {
        var events = storage.loadPendingEvents()

        let event: [String: Any] = [
            "endpoint": endpoint,
            "payload": payload,
            "queued_at": ISO8601DateFormatter().string(from: Date()),
        ]

        events.append(event)
        try? storage.savePendingEvents(events)
    }
}

// MARK: - Universal Consent

public extension ConsentService {
    /// Normalize a user identifier before hashing: Unicode NFC → trim → lowercase.
    ///
    /// CANONICAL CONTRACT (TRUST-1843 — identical across all repos, do not deviate):
    /// every site that computes a user hash MUST apply these three steps in this order,
    /// so the same person yields the same hash from web, iOS, Android, and the
    /// customer's own backend helper. Skipping this silently splits one user into
    /// multiple records and their consent stops following them across devices.
    ///
    /// The edge handler that validates these hashes computes "SHA-256 over the normalized
    /// user identifier" the same way; see the TRUST-1843 design for the full derivation.
    ///
    /// `precomposedStringWithCanonicalMapping` is NFC. `lowercased()` is deliberately
    /// used over `lowercased(with:)`: the Unicode default mapping is locale-independent,
    /// so a Turkish-locale device cannot map "I" to the dotless "ı" and hash the same
    /// identifier differently than the customer's backend does.
    static func normalizeUserIdentifier(_ identifier: String) -> String {
        identifier
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Compute the Universal Consent user hash.
    ///
    /// `SHA-256("{dgCustomerId}:{consentProjectId}:{normalizedIdentifier}")` rendered as
    /// lowercase hex (64 chars) via CryptoKit — no third-party dependency. The identifier
    /// is normalized first via ``normalizeUserIdentifier(_:)`` — see the contract note there.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    static func userHash(
        dgCustomerId: String,
        consentProjectId: String,
        identifier: String
    ) -> String {
        let input = "\(dgCustomerId):\(consentProjectId):\(normalizeUserIdentifier(identifier))"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Reconcile stored preferences against a GPC signal on-device.
    ///
    /// The Universal Consent API returns raw, unreconciled data. Clients MUST reconcile
    /// GPC locally before acting: when `gpc == true`, every non-essential category is
    /// forced off regardless of what the stored map says (effective = stored ∘ GPC).
    /// Essential/always-on categories are always preserved.
    static func reconcileGPC(
        preferences: ConsentPreferences,
        gpc: Bool,
        essentialCategoryKeys: Set<String>
    ) -> ConsentPreferences {
        guard gpc else { return preferences }

        let reconciled = preferences.cookieOptions.map { option -> CategoryConsent in
            guard essentialCategoryKeys.contains(option.gtmKey) else {
                return CategoryConsent(gtmKey: option.gtmKey, isEnabled: false)
            }
            return option
        }
        return ConsentPreferences(isCustomised: preferences.isCustomised, cookieOptions: reconciled)
    }

    /// Register a user identifier and sync their consent to the Universal Consent API.
    ///
    /// The SDK does NOT compute the HMAC. It invokes the customer-provided `getSignature`
    /// closure (which calls the customer's own backend) to obtain
    /// `{ signature, keyId, timestamp }` and attaches them as headers. The shared secret
    /// never touches the device. GPC is reconciled on-device before the write.
    ///
    /// - Parameters:
    ///   - identifier: The user identifier (email, account id, …). Normalized (NFC →
    ///     trim → lowercase) before hashing, so casing and stray whitespace cannot
    ///     split one user into multiple records.
    ///   - preferences: The consent preferences to sync.
    ///   - config: The consent configuration (must carry `consentProjectId`).
    ///   - apiKey: Customer API key. Sent as `X-DG-Api-Key` on EVERY request (reads
    ///     and writes) so the CloudFront Function can resolve customer/tier/secret
    ///     from KVS — the edge needs it on writes to locate the HMAC secret to verify.
    ///   - gpc: Live GPC signal; when true, non-essential categories are suppressed.
    ///   - essentialCategoryKeys: GTM keys that must never be suppressed by GPC.
    ///   - getSignature: Customer-provided signature provider, invoked per attempt.
    ///   - completion: Completion handler with result.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    func setUserIdentifier(
        _ identifier: String,
        preferences: ConsentPreferences,
        config: ConsentConfig,
        apiKey: String,
        gpc: Bool = false,
        essentialCategoryKeys: Set<String> = [],
        getSignature: @escaping UniversalConsentSignatureProvider,
        completion: @escaping (Result<Void, ConsentError>) -> Void
    ) {
        // Reject an identifier that is empty AFTER normalizing: SHA-256 over a bare
        // "{customerId}:{projectId}:" prefix is a deterministic value shared by every
        // such caller in the tenant, so it would collide distinct users onto one consent
        // record. Checking the raw string is not enough — "   " trims away to nothing.
        guard !ConsentService.normalizeUserIdentifier(identifier).isEmpty else {
            completion(.failure(.invalidConfiguration(
                "identifier must not be empty for Universal Consent"
            )))
            return
        }

        // Honor the server-published feature gate: `universalConsent.enabled` is the
        // remote kill switch (mirrors the `showBanner` guard). When it is absent or
        // false, do not write — the backend can disable the feature without an app release.
        guard config.universalConsent?.enabled == true else {
            completion(.failure(.invalidConfiguration(
                "Universal Consent is not enabled in the current configuration"
            )))
            return
        }

        // A BLANK projectId is as missing as a nil one: it would hash
        // "{customerId}::{identifier}", dropping the project scope entirely, so the same
        // person would land on one shared record across every project in the tenant. A
        // published config with `"consentProjectId": ""` decodes to an empty string, not nil.
        guard let projectId = config.consentProjectId,
              !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(.invalidConfiguration(
                "consentProjectId is required for Universal Consent"
            )))
            return
        }

        let userHash = Self.userHash(
            dgCustomerId: config.dgCustomerId,
            consentProjectId: projectId,
            identifier: identifier
        )

        // MANDATORY: reconcile GPC on-device before writing — the server stores raw data.
        let effective = Self.reconcileGPC(
            preferences: preferences,
            gpc: gpc,
            essentialCategoryKeys: essentialCategoryKeys
        )

        let payload = universalConsentPayload(
            userHash: userHash,
            preferences: effective,
            config: config
        )

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(.failure(.parseError("Failed to encode universal consent payload")))
            return
        }

        let url = buildURL(path: "/universal_consent")

        networkClient.retryWithBackoff(
            operation: { operationCompletion in
                // Invoke the customer signature provider per attempt so an expired
                // signature can be re-minted on retry. Secret never on device.
                self.performSignedWrite(
                    url: url,
                    body: body,
                    apiKey: apiKey,
                    getSignature: getSignature,
                    completion: operationCompletion
                )
            },
            completion: completion
        )
    }

    /// Build the Universal Consent write payload. `cookieOptions` is a MAP of `{ gtmKey: Bool }`.
    private func universalConsentPayload(
        userHash: String,
        preferences: ConsentPreferences,
        config: ConsentConfig
    ) -> [String: Any] {
        var cookieOptions: [String: Bool] = [:]
        for option in preferences.cookieOptions {
            cookieOptions[option.gtmKey] = option.isEnabled
        }

        return [
            "customer_id": config.dgCustomerId,
            "user_hash": userHash,
            "consent_preferences": [
                "isCustomised": preferences.isCustomised,
                "cookieOptions": cookieOptions,
            ],
            "consent_mode": config.consentMode,
            "config_version": config.version,
            "platform": "ios",
        ]
    }

    /// Obtain a fresh signature from the customer provider and POST with the write headers.
    private func performSignedWrite(
        url: URL,
        body: Data,
        apiKey: String,
        getSignature: @escaping UniversalConsentSignatureProvider,
        completion: @escaping (Result<Void, ConsentError>) -> Void
    ) {
        getSignature { signatureResult in
            switch signatureResult {
            case let .failure(error):
                completion(.failure(error))
            case let .success(sig):
                // X-DG-Api-Key goes on every request (reads AND writes): the CloudFront
                // Function resolves customer/tier/secret from KVS by API key, and needs
                // it on writes to locate the HMAC secret to verify the signature.
                let headers: [String: String] = [
                    "X-DG-Api-Key": apiKey,
                    "X-DG-Signature": sig.signature,
                    "X-DG-Timestamp": String(sig.timestamp),
                    "X-DG-Key-Id": sig.keyId,
                    "X-DG-Nonce": UUID().uuidString,
                ]
                self.networkClient.request(
                    url: url,
                    method: .post,
                    body: body,
                    headers: headers
                ) { result in
                    switch result {
                    case .success:
                        completion(.success(()))
                    case let .failure(error):
                        completion(.failure(error))
                    }
                }
            }
        }
    }
}
