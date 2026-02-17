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
                let dataSize = data.count

                // If data is empty (304 Not Modified), use cached config
                if data.isEmpty {
                    if let cachedConfig = self.storage.loadConfigCache() {
                        completion(.success(cachedConfig))
                    } else {
                        let msg = "304 Not Modified but no cached config. Size: \(dataSize)"
                        completion(.failure(.parseError(msg)))
                    }
                    return
                }

                do {
                    let config = try JSONDecoder().decode(ConsentConfig.self, from: data)

                    // Cache the configuration
                    try self.storage.saveConfigCache(config)

                    completion(.success(config))
                } catch {
                    let preview = String(decoding: data.prefix(200), as: UTF8.self)
                    let detailedError = "Parse failed (\(dataSize) bytes): \(preview)"
                    // If parse fails, try cached config
                    if let cachedConfig = self.storage.loadConfigCache() {
                        completion(.success(cachedConfig))
                    } else {
                        completion(.failure(.parseError(detailedError)))
                    }
                }

            case let .failure(error):
                // If network fails, try cached config
                if let cachedConfig = self.storage.loadConfigCache() {
                    completion(.success(cachedConfig))
                } else {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Fetch configuration with retry logic
    /// - Parameters:
    ///   - url: The configuration URL
    ///   - completion: Completion handler with result
    public func fetchConfigWithRetry(
        from url: URL, completion: @escaping (Result<ConsentConfig, ConsentError>) -> Void
    ) {
        networkClient.retryWithBackoff(
            operation: { operationCompletion in
                self.fetchConfig(from: url, completion: operationCompletion)
            },
            completion: completion
        )
    }
}
