import Foundation

#if canImport(UIKit)
    import UIKit
#endif

/// Service for sending consent data to backend
public class ConsentService {
    /// SDK version reported to the backend for version-analytics telemetry.
    /// ponytail: no build-time version injection exists for this package (podspec version
    /// isn't readable at runtime); keep this in sync manually with DataGrailConsent.podspec's s.version.
    private static let sdkVersion = "1.5.0"

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

    private var currentOsVersion: String {
        #if canImport(UIKit)
            return UIDevice.current.systemVersion
        #else
            let version = ProcessInfo.processInfo.operatingSystemVersion
            return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #endif
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

        let payload = saveOpenPayload(
            config: config, consentId: consentId, localeCode: localeCode, timestamp: timestamp
        )

        var components = URLComponents(string: "https://\(privacyDomain)/save_open")
        components?.queryItems = payload.map { URLQueryItem(name: $0.key, value: "\($0.value)") }

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
                    self.queueFailedRequest(payload: payload, endpoint: "save_open")
                    completion(.failure(error))
                }
            }
        )
    }

    /// Build the field set shared by the save_open query string and its offline-retry payload
    private func saveOpenPayload(
        config: ConsentConfig, consentId: String, localeCode: String, timestamp: String
    ) -> [String: Any] {
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
            "library_version": Self.sdkVersion,
            "os_version": currentOsVersion,
        ]
        if let policyUuid = config.consentPolicy.uuid {
            payload["policy_uuid"] = policyUuid
        }
        return payload
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
