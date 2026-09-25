import Foundation

/// Service for fetching and managing consent configuration
public class ConfigService {
    private let networkClient: NetworkClient
    private let storage: ConsentStorage

    public init(networkClient: NetworkClient, storage: ConsentStorage) {
        self.networkClient = networkClient
        self.storage = storage
    }

    /// Fetch configuration from URL
    /// - Parameters:
    ///   - url: The configuration URL
    ///   - completion: Completion handler with result
    public func fetchConfig(
        from url: URL, completion: @escaping (Result<ConsentConfig, ConsentError>) -> Void
    ) {
        networkClient.request(url: url, method: .get) { [weak self] result in
            guard let self else {
                completion(.failure(.networkError("Service deallocated")))
                return
            }

            switch result {
            case let .success(data):
                self.handleConfigData(data, completion: completion)

            case let .failure(error):
                let failure: ConsentError
                if error.isClientError, case let .httpError(statusCode, _) = error {
                    failure = .configNotPublished(statusCode: statusCode)
                } else {
                    failure = error
                }
                self.completeWithCachedConfig(
                    orFailWith: failure,
                    reason: "Config fetch failed: \(error.localizedDescription)",
                    completion: completion
                )
            }
        }
    }

    private func handleConfigData(
        _ data: Data, completion: @escaping (Result<ConsentConfig, ConsentError>) -> Void
    ) {
        let dataSize = data.count

        // If data is empty (304 Not Modified), use cached config
        if data.isEmpty {
            if let cachedConfig = storage.loadConfigCache() {
                completion(.success(cachedConfig))
            } else {
                Logger.error("Config returned 304 Not Modified but no cached config exists")
                let msg = "304 Not Modified but no cached config. Size: \(dataSize)"
                completion(.failure(.parseError(msg)))
            }
            return
        }

        let config: ConsentConfig
        do {
            config = try JSONDecoder().decode(ConsentConfig.self, from: data)
        } catch {
            let preview = String(decoding: data.prefix(200), as: UTF8.self)
            let detailedError = "Parse failed (\(dataSize) bytes): \(preview)"
            completeWithCachedConfig(
                orFailWith: .parseError(detailedError),
                reason: "Config parse failed (\(dataSize) bytes): \(error)",
                completion: completion
            )
            return
        }

        do {
            try ConfigValidator.validate(config)
        } catch let error as ConsentError {
            completeWithCachedConfig(
                orFailWith: error,
                reason: "Config validation failed: \(error.localizedDescription)",
                completion: completion
            )
            return
        } catch {
            completeWithCachedConfig(
                orFailWith: .validationError(String(describing: error)),
                reason: "Config validation failed: \(error)",
                completion: completion
            )
            return
        }

        do {
            try storage.saveConfigCache(config)
        } catch {
            Logger.error("Failed to cache config: \(error)")
        }
        completion(.success(config))
    }

    private func completeWithCachedConfig(
        orFailWith error: ConsentError,
        reason: String,
        completion: @escaping (Result<ConsentConfig, ConsentError>) -> Void
    ) {
        if let cachedConfig = storage.loadConfigCache() {
            Logger.error("\(reason); using cached config")
            completion(.success(cachedConfig))
        } else {
            Logger.error("\(reason); no cached config available")
            completion(.failure(error))
        }
    }

    /// Config-fetch retry policy: the shared ``ConsentError/isRetryable(_:)`` rule, plus never
    /// retrying a validation failure (the same bytes would fail the same way).
    static func shouldRetryConfigFetch(_ error: ConsentError) -> Bool {
        if case .validationError = error { return false }
        return ConsentError.isRetryable(error)
    }

    /// Fetch configuration with retry logic
    /// - Parameters:
    ///   - url: The configuration URL
    ///   - completion: Completion handler with result
    public func fetchConfigWithRetry(
        from url: URL, completion: @escaping (Result<ConsentConfig, ConsentError>) -> Void
    ) {
        networkClient.retryWithBackoff(
            // A definite 4xx (surfaced as .configNotPublished when uncached) or an invalid config
            // gives up; 5xx/transport/parse retry (408/429 still retry). See shouldRetryConfigFetch.
            shouldRetry: Self.shouldRetryConfigFetch,
            operation: { operationCompletion in
                self.fetchConfig(from: url, completion: operationCompletion)
            },
            completion: completion
        )
    }
}
