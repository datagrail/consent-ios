import Foundation

/// Errors that can occur in the DataGrail Consent SDK
public enum ConsentError: LocalizedError {
    case notInitialized
    case invalidConfiguration(String)
    case invalidConfigUrl(String)
    case networkError(String)
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
        case let .parseError(message):
            return "Failed to parse configuration: \(message)"
        case let .storageError(message):
            return "Storage error: \(message)"
        case let .validationError(message):
            return "Validation error: \(message)"
        }
    }
}
