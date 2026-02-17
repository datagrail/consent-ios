import Foundation

#if canImport(UIKit)
    import UIKit
#endif

/// Main entry point for DataGrail Consent SDK
public class DataGrailConsent {
    /// Shared singleton instance
    public static let shared = DataGrailConsent()

    private var manager: ConsentManager?
    private var configUrl: URL?
    private var _onConsentChangedCallback: ((ConsentPreferences) -> Void)?
    private let callbackLock = NSLock()

    private var onConsentChangedCallback: ((ConsentPreferences) -> Void)? {
        get {
            callbackLock.lock()
            defer { callbackLock.unlock() }
            return _onConsentChangedCallback
        }
        set {
            callbackLock.lock()
            defer { callbackLock.unlock() }
            _onConsentChangedCallback = newValue
        }
    }

    private init() {}

    // MARK: - Initialization

    /// Initialize the DataGrail Consent SDK
    /// - Parameters:
    ///   - configUrl: URL to fetch consent configuration from
    ///   - completion: Completion handler with result
    public func initialize(
        configUrl: URL,
        completion: @escaping (Result<Void, ConsentError>) -> Void
    ) {
        // Validate URL scheme
        guard let scheme = configUrl.scheme, scheme == "https" || scheme == "http" else {
            DispatchQueue.main.async {
                completion(
                    .failure(.invalidConfiguration("Config URL must use http or https scheme")))
            }
            return
        }

        // Validate URL host
        guard configUrl.host != nil else {
            DispatchQueue.main.async {
                completion(.failure(.invalidConfiguration("Config URL must have a valid host")))
            }
            return
        }

        self.configUrl = configUrl

        let storage = ConsentStorage()
        let networkClient = NetworkClient()
        let configService = ConfigService(
            networkClient: networkClient,
            storage: storage
        )

        // Extract privacy domain from config URL
        let privacyDomain = configUrl.host ?? "consent.datagrail.io"

        let consentService = ConsentService(
            networkClient: networkClient,
            storage: storage,
            privacyDomain: privacyDomain
        )

        let manager = ConsentManager(
            storage: storage,
            configService: configService,
            consentService: consentService
        )

        self.manager = manager

        // Load configuration
        manager.loadConfig(from: configUrl) { result in
            switch result {
            case .success:
                // Retry any pending requests on initialization
                manager.retryPendingRequests { _, _ in
                    // Silent retry, don't block initialization
                }
                completion(.success(()))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Consent Status

    /// Check if consent banner should be automatically displayed
    /// Returns true when:
    /// - showBanner is true in config
    /// - User has not saved consent settings, OR config version has changed
    /// - Returns: true if banner should be auto-displayed, false otherwise
    /// - Throws: ConsentError.notInitialized if SDK not initialized
    public func shouldDisplayBanner() throws -> Bool {
        guard let manager else {
            throw ConsentError.notInitialized
        }
        return manager.shouldDisplayBanner()
    }

    /// Check if user has saved consent preferences
    /// - Returns: true if user has saved preferences, false otherwise
    /// - Throws: ConsentError.notInitialized if SDK not initialized
    public func hasUserConsent() throws -> Bool {
        guard let manager else {
            throw ConsentError.notInitialized
        }
        return manager.hasUserConsent()
    }

    /// Get user's saved consent preferences
    /// - Returns: Saved preferences, or nil if user hasn't saved consent yet
    /// - Throws: ConsentError.notInitialized if SDK not initialized
    public func getUserPreferences() throws -> ConsentPreferences? {
        guard let manager else {
            throw ConsentError.notInitialized
        }
        return manager.getUserPreferences()
    }

    /// Get categories with their current consent state
    /// Returns saved preferences if available, otherwise returns default preferences from initialCategories
    /// Use this to always get category status regardless of whether the user has saved consent
    /// - Returns: Consent preferences representing the current category state
    /// - Throws: ConsentError.notInitialized if SDK not initialized
    public func getCategories() throws -> ConsentPreferences? {
        guard let manager else {
            throw ConsentError.notInitialized
        }
        return manager.getCategories()
    }

    /// Get the current configuration (for debugging)
    /// - Returns: Current config, or nil if not initialized
    public func getConfig() -> ConsentConfig? {
        manager?.config
    }

    /// Check if a specific category is enabled
    /// - Parameter category: The category GTM key (e.g., "category_marketing")
    /// - Returns: true if enabled, false otherwise
    /// - Throws: ConsentError.notInitialized if SDK not initialized
    public func isCategoryEnabled(_ category: String) throws -> Bool {
        guard let manager else {
            throw ConsentError.notInitialized
        }
        return manager.isCategoryEnabled(category)
    }

    // MARK: - Consent Management

    /// Save consent preferences
    /// - Parameters:
    ///   - preferences: The preferences to save
    ///   - completion: Completion handler with result
    public func savePreferences(
        _ preferences: ConsentPreferences,
        completion: @escaping (Result<Void, ConsentError>) -> Void
    ) {
        guard let manager else {
            completion(.failure(.notInitialized))
            return
        }

        manager.savePreferences(preferences) { [weak self] result in
            if case .success = result {
                // Notify callback on main thread
                DispatchQueue.main.async {
                    self?.onConsentChangedCallback?(preferences)
                }
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// Accept all categories
    /// - Parameter completion: Completion handler with result
    public func acceptAll(completion: @escaping (Result<Void, ConsentError>) -> Void) {
        guard let manager else {
            completion(.failure(.notInitialized))
            return
        }

        guard let defaultPreferences = manager.getDefaultPreferences() else {
            completion(.failure(.notInitialized))
            return
        }

        // Enable all categories
        let allEnabled = ConsentPreferences(
            isCustomised: true,
            cookieOptions: defaultPreferences.cookieOptions.map {
                CategoryConsent(gtmKey: $0.gtmKey, isEnabled: true)
            }
        )

        savePreferences(allEnabled, completion: completion)
    }

    /// Reject all non-essential categories
    /// - Parameter completion: Completion handler with result
    public func rejectAll(completion: @escaping (Result<Void, ConsentError>) -> Void) {
        guard let manager else {
            completion(.failure(.notInitialized))
            return
        }

        guard let defaultPreferences = manager.getDefaultPreferences() else {
            completion(.failure(.notInitialized))
            return
        }

        // Only enable essential/always-on categories
        let essentialCategories = manager.getEssentialCategories()
        let onlyEssential = ConsentPreferences(
            isCustomised: true,
            cookieOptions: defaultPreferences.cookieOptions.map {
                CategoryConsent(
                    gtmKey: $0.gtmKey,
                    isEnabled: essentialCategories.contains($0.gtmKey)
                )
            }
        )

        savePreferences(onlyEssential, completion: completion)
    }

    /// Reset all consent data
    public func reset() {
        manager?.reset()
    }

    // MARK: - Banner Display

    /// Track that the banner was shown
    /// - Parameter completion: Completion handler with result
    public func trackBannerShown(completion: @escaping (Result<Void, ConsentError>) -> Void) {
        guard let manager else {
            completion(.failure(.notInitialized))
            return
        }

        manager.trackBannerOpen(completion: completion)
    }

    // MARK: - Callbacks

    /// Set callback to be notified when consent changes
    /// - Parameter callback: Callback to invoke with new preferences
    public func onConsentChanged(_ callback: @escaping (ConsentPreferences) -> Void) {
        onConsentChangedCallback = callback
    }

    // MARK: - Utility

    /// Retry any pending API requests
    /// - Parameter completion: Completion handler with (successCount, failureCount)
    public func retryPendingRequests(completion: @escaping (Int, Int) -> Void) {
        guard let manager else {
            completion(0, 0)
            return
        }

        manager.retryPendingRequests(completion: completion)
    }

    // MARK: - UI

    #if canImport(UIKit)
        /// Show the consent banner UI in modal style
        /// - Parameters:
        ///   - presentingViewController: The view controller to present from
        ///   - completion: Called when user saves preferences or dismisses (nil if dismissed)
        public func showBanner(
            from presentingViewController: UIViewController,
            completion: @escaping (ConsentPreferences?) -> Void
        ) {
            showBanner(from: presentingViewController, style: .modal, completion: completion)
        }

        /// Show the consent banner UI with specified display style
        /// - Parameters:
        ///   - presentingViewController: The view controller to present from
        ///   - style: Display style (.modal or .fullScreen)
        ///   - completion: Called when user saves preferences or dismisses (nil if dismissed)
        public func showBanner(
            from presentingViewController: UIViewController,
            style: BannerDisplayStyle,
            completion: @escaping (ConsentPreferences?) -> Void
        ) {
            guard let manager, let config = manager.config else {
                completion(nil)
                return
            }

            // Use getCategories() to get effective preferences (saved or default from initialCategories)
            let currentPreferences = manager.getCategories()
            let bannerVC = BannerViewController(
                config: config,
                initialPreferences: currentPreferences,
                displayStyle: style,
                completion: { [weak self] preferences in
                    guard let self, let preferences else {
                        completion(nil)
                        return
                    }

                    // Save preferences
                    self.savePreferences(preferences) { result in
                        switch result {
                        case .success:
                            completion(preferences)
                        case .failure:
                            completion(nil)
                        }
                    }
                }
            )

            presentingViewController.present(bannerVC, animated: true)
        }
    #endif
}
