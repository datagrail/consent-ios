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
    /// NOTE: This case is new as of 1.7.0. Non-2xx responses previously surfaced as
    /// ``networkError``; they now surface here so retry logic can branch on the status code
    /// (see ``isClientError``). This is a source-breaking change for host apps that switch
    /// exhaustively over `ConsentError` — add a case for `.httpError` (or an `@unknown default`).
    /// Intentional and release-noted; see the PR's `breaking-change` label.
    case httpError(statusCode: Int, message: String)
    case parseError(String)
    case storageError(String)
    case validationError(String)
    /// The customer-provided `getSignature` callback did not return within
    /// ``ConsentService/universalConsentSignatureTimeout``. The Universal Consent write is
    /// abandoned rather than left hanging on a signer the SDK does not control and that may
    /// never call back. Not retried: a signer that already blew the timeout budget would just
    /// blow it again.
    case signatureTimeout

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
        case .signatureTimeout:
            return "Signature request timed out: the getSignature callback did not return in time."
        }
    }

    /// A definitive 4xx response — the server rejected the request as bad (malformed payload,
    /// rejected signature/key, 422). Retrying the identical request cannot succeed, so operations
    /// that re-invoke an external service per attempt (e.g. a customer's signing backend) must
    /// not retry it. 5xx and transport failures are retryable and are NOT client errors.
    ///
    /// 408 (Request Timeout) and 429 (Too Many Requests) are deliberately EXCLUDED: neither is a
    /// permanent rejection. 408 is a transient timeout and 429 is a rate-limit that clears with
    /// time, so both must remain retryable (with backoff). This mirrors the web SDK's
    /// `isRetryableStatus` (`status === 408 || status === 429`). Treating either as a client error
    /// would make a timed-out or rate-limited UC read/write give up after a single attempt.
    public var isClientError: Bool {
        if case let .httpError(statusCode, _) = self {
            return (400 ..< 500).contains(statusCode) && statusCode != 429 && statusCode != 408
        }
        return false
    }

    /// The default retry-eligibility policy for ``NetworkClient/retryWithBackoff(maxAttempts:baseDelay:shouldRetry:operation:completion:)``:
    /// retry any failure EXCEPT a definitive 4xx client error, which cannot succeed on replay
    /// (see ``isClientError``; 408 and 429 stay retryable). Extracted so every retried call site
    /// (`savePreferences`, `saveOpen`, `getUniversalConsent`, `setUserIdentifier`, and
    /// `ConfigService.fetchConfigWithRetry`) shares ONE predicate and a future site cannot
    /// silently omit or invert it (e.g. `{ $0.isClientError }`). Call sites with an extra
    /// rule (e.g. the signed write also refusing to retry `.signatureTimeout`) compose this.
    public static func isRetryable(_ error: ConsentError) -> Bool {
        !error.isClientError
    }
}
