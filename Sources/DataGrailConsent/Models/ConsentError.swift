import Foundation

/// Errors that can occur in the DataGrail Consent SDK
public enum ConsentError: LocalizedError {
    case notInitialized
    case invalidConfiguration(String)
    case invalidConfigUrl(String)
    case networkError(String)
    /// A non-2xx HTTP response, carrying the status code so callers can decide whether
    /// retrying could help. Transport-level failures stay ``networkError``.
    case httpError(statusCode: Int, message: String)
    case parseError(String)
    case storageError(String)
    case validationError(String)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "DataGrailConsent not initialized. Call DataGrailConsent.initialize() first."
        case let .invalidConfiguration(message):
            return "Invalid configuration: \(message)"
        case let .invalidConfigUrl(url):
            return "Invalid configuration URL: \(url)"
        case let .networkError(message):
            return "Network error: \(message)"
        case let .httpError(statusCode, message):
            return "HTTP \(statusCode): \(message)"
        case let .parseError(message):
            return "Failed to parse configuration: \(message)"
        case let .storageError(message):
            return "Storage error: \(message)"
        case let .validationError(message):
            return "Validation error: \(message)"
        }
    }

    /// A 4xx response — the server rejected the request as bad (malformed payload, rejected
    /// signature/key, 422). Retrying the identical request cannot succeed, so operations that
    /// re-invoke an external service per attempt (e.g. a customer's signing backend) must not
    /// retry it. 5xx and transport failures are retryable and are NOT client errors.
    public var isClientError: Bool {
        if case let .httpError(statusCode, _) = self {
            return (400 ..< 500).contains(statusCode)
        }
        return false
    }
}
