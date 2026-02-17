import Foundation

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

        let payload: [String: Any] = [
            "dg_customer_id": config.dgCustomerId,
            "consent_id": storage.getOrCreateUniqueId(),
            "config_version": config.version,
            "is_customised": preferences.isCustomised,
            "cookie_options": preferences.cookieOptions.map { option in
                [
                    "gtm_key": option.gtmKey,
                    "is_enabled": option.isEnabled,
                ]
            },
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]

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

    /// Save banner open event to backend
    /// - Parameters:
    ///   - config: The consent configuration
    ///   - completion: Completion handler with result
    public func saveOpen(
        config: ConsentConfig,
        completion: @escaping (Result<Void, ConsentError>) -> Void
    ) {
        let consentId = storage.getOrCreateUniqueId()

        var components = URLComponents(string: "https://\(privacyDomain)/save_open")
        components?.queryItems = [
            URLQueryItem(name: "dg_customer_id", value: config.dgCustomerId),
            URLQueryItem(name: "consent_id", value: consentId),
            URLQueryItem(name: "config_version", value: config.version),
            URLQueryItem(name: "timestamp", value: ISO8601DateFormatter().string(from: Date())),
        ]

        guard let url = components?.url else {
            completion(.failure(.networkError("Invalid URL")))
            return
        }

        networkClient.retryWithBackoff(
            operation: { operationCompletion in
                self.networkClient.request(
                    url: url,
                    method: .get,
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
                    let payload: [String: Any] = [
                        "dg_customer_id": config.dgCustomerId,
                        "consent_id": consentId,
                        "config_version": config.version,
                    ]
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
                components?.queryItems = payload.map { URLQueryItem(name: $0.key, value: "\($0.value)") }

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
