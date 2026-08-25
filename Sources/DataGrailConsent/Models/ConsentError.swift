import Foundation

/// Errors that can occur in the DataGrail Consent SDK
public enum ConsentError: LocalizedError {
    case notInitialized
    case invalidConfiguration(String)
    case invalidConfigUrl(String)
    case networkError(String)
    /// A non-2xx HTTP response, carrying the status code so callers can decide whether
    /// retrying could help. Transport-level failures stay ``networkError``.
    ///
    /// NOTE: This case is new as of 2.0. Non-2xx responses previously surfaced as
    /// ``networkError``; they now surface here so retry logic can branch on the status code
    /// (see ``isClientError``). This is a source-breaking change for host apps that switch
    /// exhaustively over `ConsentError` — add a case for `.httpError` (or an `@unknown default`).
    /// Intentional and release-noted; see the PR's `breaking-change` label.
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

    /// A definitive 4xx response — the server rejected the request as bad (malformed payload,
    /// rejected signature/key, 422). Retrying the identical request cannot succeed, so operations
    /// that re-invoke an external service per attempt (e.g. a customer's signing backend) must
    /// not retry it. 5xx and transport failures are retryable and are NOT client errors.
    ///
    /// 429 (Too Many Requests) is deliberately EXCLUDED: it is not a permanent rejection but a
    /// rate-limit that clears with time, so it must remain retryable (with backoff). Treating it
    /// as a client error would make a rate-limited UC read/write give up after a single attempt.
    public var isClientError: Bool {
        if case let .httpError(statusCode, _) = self {
            return (400 ..< 500).contains(statusCode) && statusCode != 429
        }
        return false
    }
}
