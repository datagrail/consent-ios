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

    /// Reconcile stored preferences against the device's live tracking signal.
    ///
    /// The Universal Consent API returns raw, unreconciled data. Clients MUST reconcile
    /// the live signal locally before acting: when the signal suppresses (ATT `denied`
    /// or `restricted`), every non-essential category is forced off regardless of what
    /// the stored map says. Essential/always-on categories are always preserved.
    ///
    /// Suppression is one-directional by design. A live signal may only turn categories
    /// OFF — it never turns one on. ATT `authorized` is permission to track, not consent
    /// to marketing categories, and `notDetermined` is the absence of an answer rather
    /// than a refusal, so neither changes the stored map in either direction.
    static func reconcile(
        preferences: ConsentPreferences,
        trackingSignal: TrackingSignal,
        essentialCategoryKeys: Set<String>
    ) -> ConsentPreferences {
        guard trackingSignal.suppressesNonEssential else { return preferences }

        let reconciled = preferences.cookieOptions.map { option -> CategoryConsent in
            guard essentialCategoryKeys.contains(option.gtmKey) else {
                return CategoryConsent(gtmKey: option.gtmKey, isEnabled: false)
            }
            return option
        }
        return ConsentPreferences(isCustomised: preferences.isCustomised, cookieOptions: reconciled)
    }

    /// Reconcile a wire-format `cookieOptions` MAP against an opt-out signal.
    ///
    /// The map overload of ``reconcile(preferences:trackingSignal:essentialCategoryKeys:)``,
    /// for the read path — the wire format is a map, so converting to an array first would
    /// be lossy busywork. `suppress` is a decision, not a signal, because the read path
    /// combines two sources (the record's stored `gpc` and this device's live signal) and
    /// the more privacy-protective wins.
    static func reconcile(
        cookieOptions: [String: Bool],
        suppress: Bool,
        essentialCategoryKeys: Set<String>
    ) -> [String: Bool] {
        guard suppress else { return cookieOptions }
        var reconciled: [String: Bool] = [:]
        for (key, enabled) in cookieOptions {
            reconciled[key] = essentialCategoryKeys.contains(key) ? enabled : false
        }
        return reconciled
    }

    /// Validate the Universal Consent preconditions and return the user hash.
    ///
    /// Shared by the read and write paths, which must agree on all three checks — if a value
    /// is unsafe to write under, it is unsafe to read under, and a hash computed differently
    /// on each path would silently split one user across two records.
    ///
    /// - An identifier empty AFTER normalization hashes the bare `"{customerId}:{projectId}:"`
    ///   prefix — a deterministic value every such caller in the tenant shares, collapsing
    ///   unrelated users onto one record. Checking the raw string is not enough: `"   "` trims
    ///   away to nothing.
    /// - A BLANK `consentProjectId` is as missing as a nil one: it hashes
    ///   `"{customerId}::{identifier}"`, dropping the project scope so the same person lands on
    ///   one shared record across every project in the tenant. A published config with
    ///   `"consentProjectId": ""` decodes to an empty string, not nil.
    /// - `universalConsent.enabled` is the server-published kill switch, so the backend can
    ///   disable the feature without an app release.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    static func validatedUserHash(identifier: String, config: ConsentConfig) throws -> String {
        guard !normalizeUserIdentifier(identifier).isEmpty else {
            throw ConsentError.invalidConfiguration(
                "identifier must not be empty for Universal Consent"
            )
        }

        guard config.universalConsent?.enabled == true else {
            throw ConsentError.invalidConfiguration(
                "Universal Consent is not enabled in the current configuration"
            )
        }

        guard let projectId = config.consentProjectId,
              !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConsentError.invalidConfiguration(
                "consentProjectId is required for Universal Consent"
            )
        }

        return userHash(
            dgCustomerId: config.dgCustomerId,
            consentProjectId: projectId,
            identifier: identifier
        )
    }

    /// Read a user's stored Universal Consent record for cross-device rehydration.
    ///
    /// `GET /universal_consent?customer_id=..&user_hash=..` with an `X-DG-Api-Key` header.
    /// Reads are unsigned — only writes carry an HMAC — but the API key is still required so
    /// the CloudFront Function can resolve the customer from KVS.
    ///
    /// The returned record is RAW and UNRECONCILED. Callers must apply signal reconciliation
    /// before acting on it; ``ConsentManager/fetchUniversalConsent(_:apiKey:trackingSignal:completion:)``
    /// does this for you.
    ///
    /// - Returns: the parsed record, or `nil` when the server reports `not_found`. A miss is
    ///   the absence of a signal, NOT an opt-out — the two lead to opposite banner decisions,
    ///   so they must not collapse into one value.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    func getUniversalConsent(
        _ identifier: String,
        config: ConsentConfig,
        apiKey: String,
        completion: @escaping (Result<UniversalConsentRecord?, ConsentError>) -> Void
    ) {
        let userHash: String
        do {
            userHash = try Self.validatedUserHash(identifier: identifier, config: config)
        } catch let error as ConsentError {
            completion(.failure(error))
            return
        } catch {
            completion(.failure(.invalidConfiguration(error.localizedDescription)))
            return
        }

        guard var components = URLComponents(
            url: buildURL(path: "/universal_consent"),
            resolvingAgainstBaseURL: false
        ) else {
            completion(.failure(.invalidConfiguration("Could not build Universal Consent URL")))
            return
        }
        components.queryItems = [
            URLQueryItem(name: "customer_id", value: config.dgCustomerId),
            URLQueryItem(name: "user_hash", value: userHash),
        ]
        guard let url = components.url else {
            completion(.failure(.invalidConfiguration("Could not build Universal Consent URL")))
            return
        }

        networkClient.retryWithBackoff(
            operation: { operationCompletion in
                self.networkClient.request(
                    url: url,
                    method: .get,
                    headers: ["X-DG-Api-Key": apiKey],
                    completion: operationCompletion
                )
            },
            completion: { result in
                switch result {
                case let .success(data):
                    do {
                        let record = try JSONDecoder().decode(UniversalConsentRecord.self, from: data)
                        completion(.success(record.isFound ? record : nil))
                    } catch {
                        completion(.failure(.parseError(
                            "Failed to decode universal consent record: \(error.localizedDescription)"
                        )))
                    }
                case let .failure(error):
                    completion(.failure(error))
                }
            }
        )
    }

    /// Register a user identifier and sync their consent to the Universal Consent API.
    ///
    /// The SDK does NOT compute the HMAC. It invokes the customer-provided `getSignature`
    /// closure (which calls the customer's own backend) to obtain
    /// `{ signature, keyId, timestamp }` and attaches them as headers. The shared secret
    /// never touches the device. The live tracking signal is reconciled on-device before
    /// the write.
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
    ///   - trackingSignal: The device's live tracking signal. Defaults to the current
    ///     ATT status, read from the OS — pass an explicit value only when the host app
    ///     manages ATT itself. `denied`/`restricted` suppress non-essential categories;
    ///     no signal state ever enables one.
    ///   - essentialCategoryKeys: GTM keys that must never be suppressed.
    ///   - getSignature: Customer-provided signature provider, invoked per attempt.
    ///   - completion: Completion handler with result.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    func setUserIdentifier(
        _ identifier: String,
        preferences: ConsentPreferences,
        config: ConsentConfig,
        apiKey: String,
        trackingSignal: TrackingSignal = TrackingSignalReader.current(),
        essentialCategoryKeys: Set<String> = [],
        getSignature: @escaping UniversalConsentSignatureProvider,
        completion: @escaping (Result<Void, ConsentError>) -> Void
    ) {
        // Identical preconditions to the read path — see validatedUserHash for why each one
        // is load-bearing.
        let userHash: String
        do {
            userHash = try Self.validatedUserHash(identifier: identifier, config: config)
        } catch let error as ConsentError {
            completion(.failure(error))
            return
        } catch {
            completion(.failure(.invalidConfiguration(error.localizedDescription)))
            return
        }

        // MANDATORY: reconcile the live signal on-device before writing — the server
        // stores raw data.
        let effective = Self.reconcile(
            preferences: preferences,
            trackingSignal: trackingSignal,
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
