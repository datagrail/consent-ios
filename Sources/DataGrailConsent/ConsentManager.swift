import Foundation

/// Manages consent state and coordinates between storage, network, and configuration
public class ConsentManager {
    private let storage: ConsentStorage
    private let configService: ConfigService
    private let consentService: ConsentService
    private var currentConfig: ConsentConfig?

    /// Current loaded configuration (read-only)
    public var config: ConsentConfig? {
        currentConfig
    }

    public init(
        storage: ConsentStorage,
        configService: ConfigService,
        consentService: ConsentService
    ) {
        self.storage = storage
        self.configService = configService
        self.consentService = consentService
    }

    // MARK: - Configuration

    /// Load configuration from URL
    /// - Parameters:
    ///   - configUrl: URL to fetch configuration from
    ///   - completion: Completion handler with result
    public func loadConfig(
        from configUrl: URL, completion: @escaping (Result<ConsentConfig, ConsentError>) -> Void
    ) {
        configService.fetchConfigWithRetry(from: configUrl) { [weak self] result in
            switch result {
            case let .success(config):
                self?.currentConfig = config
                completion(.success(config))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Consent Check

    /// Check if consent banner should be automatically displayed
    /// Returns true when:
    /// - showBanner is true in config
    /// - User has not saved consent settings, OR config version has changed
    /// - Returns: true if banner should be auto-displayed, false otherwise
    public func shouldDisplayBanner() -> Bool {
        guard let config = currentConfig else {
            return false
        }

        // Check if showBanner is enabled in config
        if !config.showBanner {
            return false
        }

        // Check if preferences exist
        let preferences = storage.loadPreferences()

        // If no preferences, should display
        if preferences == nil {
            return true
        }

        // Check if config version has changed
        let storedVersion = storage.loadConfigVersion()
        if storedVersion != config.version {
            return true
        }

        return false
    }

    /// Check if user has saved consent preferences
    /// - Returns: true if user has saved preferences, false otherwise
    public func hasUserConsent() -> Bool {
        storage.loadPreferences() != nil
    }

    // MARK: - Preferences

    /// Get user's saved consent preferences
    /// - Returns: Saved preferences, or nil if user hasn't saved consent yet
    public func getUserPreferences() -> ConsentPreferences? {
        storage.loadPreferences()
    }

    /// Get categories with their current consent state
    /// Returns saved preferences if available, otherwise returns default preferences from initialCategories
    /// - Returns: Consent preferences representing the current category state
    public func getCategories() -> ConsentPreferences? {
        if let saved = storage.loadPreferences() {
            return saved
        }
        return getDefaultPreferences()
    }

    /// Get all category GTM keys from config
    /// Combines initialCategories.initial with any categories found in consent layers
    private func getAllCategoryKeys(_ config: ConsentConfig) -> [String] {
        var categories = Set<String>()

        // Add categories from initialCategories
        categories.formUnion(config.initialCategories.initial)

        // Also scan consent layers for any additional categories
        for layer in config.layout.consentLayers.values {
            for element in layer.elements {
                if let layerCategories = element.consentLayerCategories {
                    for category in layerCategories {
                        categories.insert(category.gtmKey)
                    }
                }
            }
        }

        return Array(categories)
    }

    /// Get default preferences based on configuration
    /// - Returns: Default preferences with initial categories enabled
    public func getDefaultPreferences() -> ConsentPreferences? {
        guard let config = currentConfig else {
            return nil
        }

        let cookieOptions = getAllCategoryKeys(config).map { category in
            CategoryConsent(gtmKey: category, isEnabled: true)
        }

        return ConsentPreferences(
            isCustomised: false,
            cookieOptions: cookieOptions
        )
    }

    /// Save consent preferences
    /// - Parameters:
    ///   - preferences: The preferences to save
    ///   - completion: Completion handler with result
    public func savePreferences(
        _ preferences: ConsentPreferences,
        completion: @escaping (Result<Void, ConsentError>) -> Void
    ) {
        guard let config = currentConfig else {
            completion(.failure(.notInitialized))
            return
        }

        do {
            // Save locally
            try storage.savePreferences(preferences)
            storage.saveConfigVersion(config.version)

            // Send to backend
            consentService.savePreferences(
                preferences: preferences,
                config: config
            ) { result in
                completion(result)
            }
        } catch let error as ConsentError {
            completion(.failure(error))
        } catch {
            completion(.failure(.storageError(error.localizedDescription)))
        }
    }

    /// Track banner open event
    /// - Parameter completion: Completion handler with result
    public func trackBannerOpen(completion: @escaping (Result<Void, ConsentError>) -> Void) {
        guard let config = currentConfig else {
            completion(.failure(.notInitialized))
            return
        }

        consentService.saveOpen(config: config, completion: completion)
    }

    /// Check if a specific category is enabled
    /// - Parameter category: The category GTM key to check
    /// - Returns: true if enabled, false otherwise
    public func isCategoryEnabled(_ category: String) -> Bool {
        guard let preferences = storage.loadPreferences() else {
            // No preferences - check if it's in initial categories
            return currentConfig?.initialCategories.initial.contains(category) ?? false
        }

        return preferences.isCategoryEnabled(category)
    }

    /// Normalize element type by removing ConsentLayer prefix and Element suffix
    private func normalizeElementType(_ type: String) -> String {
        type.replacingOccurrences(of: "ConsentLayer", with: "")
            .replacingOccurrences(of: "Element", with: "")
            .lowercased()
    }

    /// Get list of essential/always-on category GTM keys from config
    /// - Returns: Array of GTM keys for categories that are always enabled
    public func getEssentialCategories() -> [String] {
        guard let config = currentConfig else {
            return []
        }

        var essentialKeys: [String] = []

        // Check all layers for categories marked as alwaysOn
        for (_, layer) in config.layout.consentLayers {
            for element in layer.elements where normalizeElementType(element.type) == "category" {
                guard let categories = element.consentLayerCategories else { continue }
                for category in categories where category.alwaysOn {
                    essentialKeys.append(category.gtmKey)
                }
            }
        }

        // Also check for categories with "essential" in the name as fallback
        for gtmKey in config.initialCategories.initial
            where gtmKey.lowercased().contains("essential") && !essentialKeys.contains(gtmKey)
        {
            essentialKeys.append(gtmKey)
        }

        return essentialKeys
    }

    // MARK: - Retry

    /// Retry any pending API requests
    /// - Parameter completion: Completion handler with (successCount, failureCount)
    public func retryPendingRequests(completion: @escaping (Int, Int) -> Void) {
        consentService.retryPendingRequests(completion: completion)
    }

    // MARK: - Reset

    /// Clear all consent data
    public func reset() {
        storage.clearAll()
        currentConfig = nil
    }
}
