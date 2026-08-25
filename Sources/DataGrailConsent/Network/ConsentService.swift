import CryptoKit
import Foundation
import Security

/// The payload the SDK hands to the customer-provided `getSignature` closure.
///
/// The SDK owns the canonical signing contract: it computes the user hash, generates the
/// timestamp and nonce, and builds ``stringToSign`` itself. The customer's callback does one
/// thing — compute `HMAC-SHA256(rawSecretBytes, payload.stringToSign)` rendered as lowercase
/// hex — and returns it with their keyId. It never builds the string, generates the nonce, or
/// manages the timestamp.
///
/// The SDK sends the SAME ``timestamp`` and ``nonce`` it folded into ``stringToSign`` as the
/// `X-DG-Timestamp` and `X-DG-Nonce` headers, so the value signed and the value on the wire
/// cannot drift — if the customer signs `payload.stringToSign` verbatim, the edge's check
/// passes by construction.
///
/// `rawSecretBytes` is the shared secret's 64 hex characters DECODED to the 32 raw key bytes —
/// the HMAC key is those bytes, NOT the ASCII hex string. Keying the HMAC with the hex string
/// is the single most common Universal Consent integration failure.
public struct UniversalConsentSigningPayload {
    /// The exact bytes to sign: `"{customerId}:{userHash}:{timestamp}:{nonce}"`. Sign this
    /// verbatim — do not re-assemble it from the fields below, or a formatting difference will
    /// silently break signature verification at the edge.
    public let stringToSign: String
    /// The DataGrail customer id, first segment of ``stringToSign``.
    public let customerId: String
    /// `SHA-256("{customerId}:{projectId}:{normalizedIdentifier}")`, second segment.
    public let userHash: String
    /// Unix timestamp (seconds, device clock) the SDK minted for this write and sends in
    /// `X-DG-Timestamp`. Third segment of ``stringToSign``.
    public let timestamp: Int64
    /// A fresh 128-bit nonce as 32 lowercase hex the SDK minted for this write and sends in
    /// `X-DG-Nonce`. Fourth segment of ``stringToSign``.
    public let nonce: String

    public init(stringToSign: String, customerId: String, userHash: String, timestamp: Int64, nonce: String) {
        self.stringToSign = stringToSign
        self.customerId = customerId
        self.userHash = userHash
        self.timestamp = timestamp
        self.nonce = nonce
    }
}

/// Signature material returned by the customer-provided `getSignature` closure.
///
/// The SDK never holds the HMAC secret and never computes the signature itself. The
/// customer's backend computes `HMAC-SHA256(rawSecretBytes, payload.stringToSign)` rendered as
/// lowercase hex and hands back this value; the SDK only attaches it as the `X-DG-Signature`
/// header. `keyId` (sent as `X-DG-Key-Id`) identifies which secret was used, supporting
/// rotation. The SDK owns the timestamp and nonce, so they are NOT part of this return.
public struct UniversalConsentSignature {
    /// Hex HMAC signature computed by the customer backend over `payload.stringToSign`.
    public let signature: String
    /// Identifies which HMAC secret was used (supports key rotation).
    public let keyId: String

    public init(signature: String, keyId: String) {
        self.signature = signature
        self.keyId = keyId
    }
}

/// Customer-provided callback that vouches for the current user by signing the SDK-built
/// payload. Result-based to match this SDK's existing callback style. The SDK invokes it per
/// write attempt — passing a freshly minted ``UniversalConsentSigningPayload`` (new timestamp
/// and nonce) each time — so a retried write is signed for its own timestamp and nonce.
public typealias UniversalConsentSignatureProvider =
    (UniversalConsentSigningPayload, @escaping (Result<UniversalConsentSignature, ConsentError>) -> Void) -> Void

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
        return hexEncoded(digest)
    }

    /// Lowercase hex encoding (two chars per byte), shared by the user hash and the nonce so
    /// the two cannot render bytes differently.
    static func hexEncoded<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Reconcile a wire-format `cookieOptions` MAP against an opt-out signal.
    ///
    /// The Universal Consent API returns raw, unreconciled data. Clients MUST reconcile the
    /// signal locally before acting: when it suppresses, every non-essential category is forced
    /// off regardless of what the stored map says. Essential/always-on categories are always
    /// enabled (and backfilled if the record omitted them).
    ///
    /// Suppression is one-directional by design — a signal may only turn categories OFF, never
    /// on. The wire format is a map, so this operates on the map directly rather than converting
    /// to an array first. `suppress` is a decision, not a signal, because the read path combines
    /// two sources (the record's stored `gpc`/`ccpaOptout` and this device's live signal) and
    /// the more privacy-protective wins.
    ///
    /// READ PATH ONLY. Never call this before a write to the Universal Consent store — the store
    /// holds raw choices and the server never merges, so persisting a suppressed map would
    /// overwrite the user's real opt-in for every device on their identifier.
    static func reconcile(
        cookieOptions: [String: Bool],
        suppress: Bool,
        essentialCategoryKeys: Set<String>
    ) -> [String: Bool] {
        var reconciled: [String: Bool] = [:]
        for (key, enabled) in cookieOptions {
            // Essential categories are always on, so they resolve to enabled regardless of the
            // stored value or the opt-out signal. Non-essential categories keep their stored
            // value unless the signal suppresses them (OFF-only — a signal never re-enables).
            reconciled[key] = essentialCategoryKeys.contains(key) ? true : (suppress ? false : enabled)
        }
        // Backfill essential categories the stored record omitted. Essential is always enabled,
        // so a key missing from an older or signal-shaped record must still resolve to enabled
        // rather than fall through to disabled after rehydration.
        for key in essentialCategoryKeys where reconciled[key] == nil {
            reconciled[key] = true
        }
        return reconciled
    }

    /// Whether a stored record's signals, combined with this device's live signal, suppress
    /// non-essential categories on read.
    ///
    /// The single source of truth for the "does an opt-out signal apply?" decision, shared by
    /// every read-path call site (`fetchUniversalConsent`, `rehydrateReturningRawPreferences`)
    /// so what an integrator inspects cannot diverge from what is persisted and drives
    /// `isCategoryEnabled`. The record's stored `gpc` and `ccpaOptout` came from the web where
    /// those signals exist; the tracking signal belongs to this device. Any of them suppresses
    /// and none can re-enable what another suppressed — consistent with the OFF-only reconcile
    /// contract. A stored CCPA "do not sell/share" opt-out is a marketing opt-out, so it must
    /// force non-essential categories off on read just as GPC does. Remaining opt-out-ish
    /// signals on the record (`gppString`, `tcfString`) get folded in here, once, when their
    /// on-device meaning is settled, rather than at each call site.
    static func suppresses(record: UniversalConsentRecord, trackingSignal: TrackingSignal) -> Bool {
        record.gpc || record.ccpaOptout || trackingSignal.suppressesNonEssential
    }

    /// Reconcile a record's raw `cookieOptions` for the read path: the single suppress
    /// decision and the OFF-only reconcile applied together, so `fetchUniversalConsent` and
    /// `rehydrateReturningRawPreferences` share one sequence rather than hand-rolling it each.
    static func reconciledCookieOptions(
        record: UniversalConsentRecord,
        rawCookieOptions: [String: Bool],
        trackingSignal: TrackingSignal,
        essentialCategoryKeys: Set<String>
    ) -> [String: Bool] {
        reconcile(
            cookieOptions: rawCookieOptions,
            suppress: suppresses(record: record, trackingSignal: trackingSignal),
            essentialCategoryKeys: essentialCategoryKeys
        )
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
            // A definite 4xx (bad/rotated key, disabled customer) will not succeed on replay,
            // so fail fast rather than burning all retries with backoff on a first-time read.
            // Same predicate the signed write uses; 5xx/transport failures still retry.
            shouldRetry: { !$0.isClientError },
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
    /// The SDK owns the signing contract but NOT the secret. On a write it computes the user
    /// hash, mints a unix `timestamp` and a 128-bit `nonce`, builds
    /// `stringToSign = "{customerId}:{userHash}:{timestamp}:{nonce}"`, and invokes the
    /// customer-provided `getSignature` closure (which calls the customer's own backend) with
    /// that payload to obtain `{ signature, keyId }`. It then attaches `X-DG-Signature`,
    /// `X-DG-Key-Id`, and the SDK's own `X-DG-Timestamp` / `X-DG-Nonce`. The shared secret
    /// never touches the device.
    ///
    /// LIMITED MODE: when `getSignature` is `nil` the SDK sends an API-key-only write (just
    /// `X-DG-Api-Key`, no signature/timestamp/nonce). Use it when the customer has not wired a
    /// signer; the edge treats it as an unauthenticated write per the tier's policy.
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
    ///   - getSignature: Customer-provided signature provider, invoked per attempt with a
    ///     freshly minted payload. `nil` selects limited (API-key-only) mode.
    ///   - completion: Completion handler with result.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    func setUserIdentifier(
        _ identifier: String,
        preferences: ConsentPreferences,
        config: ConsentConfig,
        apiKey: String,
        getSignature: UniversalConsentSignatureProvider?,
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

        // Write the RAW preferences. The store holds raw choices and the server never merges,
        // so reconciling here would persist this device's transient signal as the user's
        // choice — permanently, for every device on this identifier. ATT `denied` is a
        // cross-app-tracking answer, not a marketing opt-out: someone who opted in on the web
        // and then opens the app with ATT denied must not have that opt-in erased. Suppression
        // is a read-time view (see `reconcile`, and the read path in ConsentManager).
        let body: Data
        do {
            body = try universalConsentPayload(
                userHash: userHash,
                preferences: preferences,
                config: config
            )
        } catch let error as ConsentError {
            completion(.failure(error))
            return
        } catch {
            completion(.failure(.parseError("Failed to encode universal consent payload")))
            return
        }

        let url = buildURL(path: "/universal_consent")
        let writeRequest = UniversalConsentWriteRequest(url: url, body: body, apiKey: apiKey)

        networkClient.retryWithBackoff(
            // A hard 4xx (malformed payload, rejected signature/key, 422) will not succeed on
            // replay, and each attempt re-invokes the customer's signing backend and re-POSTs.
            // Retry only 5xx/transport failures so a bad request or a secret-rotation mismatch
            // does not amplify 5x load onto the signing service exactly when it is erroring.
            shouldRetry: { !$0.isClientError },
            operation: { operationCompletion in
                guard let getSignature else {
                    // Limited mode: no signer configured, so send an API-key-only write with
                    // no signature/timestamp/nonce headers.
                    self.performLimitedWrite(writeRequest, completion: operationCompletion)
                    return
                }
                // Mint a fresh timestamp + nonce and invoke the customer signer per attempt,
                // so a retried write is signed for its own timestamp/nonce and an expired
                // signature can be re-minted. Secret never on device.
                self.performSignedWrite(
                    writeRequest,
                    customerId: config.dgCustomerId,
                    userHash: userHash,
                    getSignature: getSignature,
                    completion: operationCompletion
                )
            },
            completion: completion
        )
    }

    /// Build the Universal Consent write payload, serialized to JSON. `cookieOptions` is a MAP
    /// of `{ gtmKey: Bool }`.
    ///
    /// The inner `consent_preferences` object is encoded from ``UniversalConsentPreferences`` —
    /// the same `Codable` model the read path decodes — rather than a hand-built literal dict, so
    /// this cross-SDK wire shape has ONE source of truth and cannot silently drift between the
    /// write and read directions.
    private func universalConsentPayload(
        userHash: String,
        preferences: ConsentPreferences,
        config: ConsentConfig
    ) throws -> Data {
        var cookieOptions: [String: Bool] = [:]
        for option in preferences.cookieOptions {
            cookieOptions[option.gtmKey] = option.isEnabled
        }

        let consentPreferences = UniversalConsentPreferences(
            isCustomised: preferences.isCustomised,
            cookieOptions: cookieOptions
        )
        let encodedPreferences = try JSONEncoder().encode(consentPreferences)
        guard let preferencesObject = try JSONSerialization.jsonObject(
            with: encodedPreferences
        ) as? [String: Any] else {
            throw ConsentError.parseError("Failed to encode universal consent preferences")
        }

        let payload: [String: Any] = [
            "customer_id": config.dgCustomerId,
            "user_hash": userHash,
            "consent_preferences": preferencesObject,
            "consent_mode": config.consentMode,
            "config_version": config.version,
            "platform": "ios",
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// The transport inputs both write modes share: where to POST, the encoded body, and the
    /// API key the edge needs on every request. Bundled so the signed and limited write helpers
    /// stay within SwiftLint's parameter-count limit without splitting three values that always
    /// travel together — this does not change the signing contract.
    private struct UniversalConsentWriteRequest {
        let url: URL
        let body: Data
        let apiKey: String
    }

    /// Mint the timestamp + nonce, build `stringToSign`, have the customer sign it, and POST
    /// with the write headers.
    ///
    /// The SDK owns the timestamp and nonce and sends the SAME values it folded into
    /// `stringToSign` (`X-DG-Timestamp` / `X-DG-Nonce`), so the bytes the customer signed and
    /// the bytes on the wire cannot drift.
    private func performSignedWrite(
        _ request: UniversalConsentWriteRequest,
        customerId: String,
        userHash: String,
        getSignature: @escaping UniversalConsentSignatureProvider,
        completion: @escaping (Result<Void, ConsentError>) -> Void
    ) {
        let timestamp = Int64(Date().timeIntervalSince1970)
        let nonce = Self.generateNonce()
        let stringToSign = "\(customerId):\(userHash):\(timestamp):\(nonce)"
        let payload = UniversalConsentSigningPayload(
            stringToSign: stringToSign,
            customerId: customerId,
            userHash: userHash,
            timestamp: timestamp,
            nonce: nonce
        )

        getSignature(payload) { signatureResult in
            switch signatureResult {
            case let .failure(error):
                completion(.failure(error))
            case let .success(sig):
                // X-DG-Api-Key goes on every request (reads AND writes): the CloudFront
                // Function resolves customer/tier/secret from KVS by API key, and needs
                // it on writes to locate the HMAC secret to verify the signature.
                // Timestamp and nonce come from the payload we just signed, never from the
                // callback — that is what guarantees the signed and sent values match.
                let headers: [String: String] = [
                    "X-DG-Api-Key": request.apiKey,
                    "X-DG-Signature": sig.signature,
                    "X-DG-Timestamp": String(payload.timestamp),
                    "X-DG-Nonce": payload.nonce,
                    "X-DG-Key-Id": sig.keyId,
                ]
                self.networkClient.request(
                    url: request.url,
                    method: .post,
                    body: request.body,
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

    /// POST a limited (API-key-only) write: no signer configured, so no signature, timestamp,
    /// or nonce headers. `X-DG-Api-Key` still goes up so the edge can resolve the customer.
    private func performLimitedWrite(
        _ request: UniversalConsentWriteRequest,
        completion: @escaping (Result<Void, ConsentError>) -> Void
    ) {
        networkClient.request(
            url: request.url,
            method: .post,
            body: request.body,
            headers: ["X-DG-Api-Key": request.apiKey]
        ) { result in
            switch result {
            case .success:
                completion(.success(()))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    /// Generate a 128-bit nonce as 32 lowercase hex characters from a CSPRNG.
    ///
    /// Prefers `SecRandomCopyBytes`; falls back to `SystemRandomNumberGenerator` (also a
    /// CSPRNG on Apple platforms) if the Security call ever reports failure. NOT a UUID —
    /// the contract requires 32 hex characters folded into the signed string.
    private static func generateNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            var rng = SystemRandomNumberGenerator()
            for index in bytes.indices {
                bytes[index] = UInt8.random(in: UInt8.min ... UInt8.max, using: &rng)
            }
        }
        return hexEncoded(bytes)
    }
}
