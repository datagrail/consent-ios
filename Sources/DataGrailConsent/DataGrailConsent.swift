import Foundation

#if canImport(UIKit)
    import UIKit
#endif

/// Main entry point for DataGrail Consent SDK
public class DataGrailConsent {
    /// Shared singleton instance
    public static let shared = DataGrailConsent()

    /// SDK log level. Default is .none (no logging in production).
    /// Set to .debug to see all internal SDK logging.
    public static var logLevel: LogLevel {
        get { Logger.logLevel }
        set { Logger.logLevel = newValue }
    }

    private var manager: ConsentManager?
    private var configUrl: URL?
    private var apiKey: String?
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
    ///   - apiKey: Optional API key for reading consent (required for QR pairing on tvOS)
    ///   - completion: Completion handler with result
    public func initialize(
        configUrl: URL,
        apiKey: String? = nil,
        completion: @escaping (Result<Void, ConsentError>) -> Void
    ) {
        self.apiKey = apiKey
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

    #if os(iOS)
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
    #elseif os(tvOS)
        /// Show the consent banner UI on tvOS (full-screen only)
        /// - Parameters:
        ///   - presentingViewController: The view controller to present from
        ///   - completion: Called when user saves preferences or dismisses (nil if dismissed)
        public func showBanner(
            from presentingViewController: UIViewController,
            completion: @escaping (ConsentPreferences?) -> Void
        ) {
            guard let manager, let config = manager.config else {
                completion(nil)
                return
            }

            // Use getCategories() to get effective preferences
            let currentPreferences = manager.getCategories()
            let bannerVC = BannerViewControllerTvOS(
                config: config,
                initialPreferences: currentPreferences,
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

        /// Show the consent banner with QR pairing on tvOS
        /// - Parameters:
        ///   - presentingViewController: The view controller to present from
        ///   - publicBaseUrl: The base URL reachable by the phone (e.g., http://192.168.1.5:8080 or https://tunnel.example.com)
        ///   - configUrl: URL to the consent config JSON (encoded in QR for phone to fetch)
        ///   - customerId: DataGrail customer ID
        ///   - userIdentifier: Optional user identifier override (if nil, auto-detect from device)
        ///   - completion: Called when user saves preferences or pairing completes (nil if dismissed/timeout)
        public func showBannerWithQRPairing(
            from presentingViewController: UIViewController,
            publicBaseUrl: String,
            configUrl: String,
            customerId: String,
            userIdentifier: String? = nil,
            completion: @escaping (ConsentPreferences?) -> Void
        ) {
            guard let manager, let config = manager.config else {
                completion(nil)
                return
            }

            // Generate user_hash
            let userHash = UserHashGenerator.generateUserHash(
                customerId: customerId,
                consentProjectId: config.consentContainerVersionId,
                deviceIdentifier: userIdentifier
            )

            // Create pairing service
            let networkClient = NetworkClient()
            let pairingService = PairingService(
                networkClient: networkClient,
                apiBaseUrl: config.privacyDomain,
                apiKey: apiKey
            )

            // Build QR URL
            guard let qrUrl = pairingService.qrURL(
                publicBaseUrl: publicBaseUrl,
                customerId: customerId,
                userHash: userHash,
                configUrl: configUrl
            ) else {
                completion(nil)
                return
            }

            // Generate QR image
            guard let qrImage = QRCodeGenerator.generateQRCode(from: qrUrl.absoluteString, size: 300) else {
                completion(nil)
                return
            }

            // Create pairing coordinator
            let coordinator = PairingCoordinator(
                pairingService: pairingService,
                customerId: customerId,
                userHash: userHash
            )

            // Setup coordinator callbacks
            coordinator.onConsentFound = { [weak self, weak coordinator] preferences in
                guard let self = self else { return }

                // Adopt remote preferences (phone already wrote to backend)
                manager.adoptRemotePreferences(preferences)

                // Notify callback
                DispatchQueue.main.async {
                    self.onConsentChangedCallback?(preferences)
                }

                // Dismiss banner and complete
                presentingViewController.dismiss(animated: true) {
                    completion(preferences)
                }

                coordinator?.stopPolling()
            }

            coordinator.onTimeout = { [weak coordinator, weak presentingViewController] in
                // Timeout: remove QR, fall back to D-pad banner (already rendered)
                Logger.warn("QR pairing timeout, falling back to D-pad banner")
                coordinator?.stopPolling()

                // Remove QR from banner if still presented
                if let presented = presentingViewController?.presentedViewController as? BannerViewControllerTvOS {
                    presented.removeQRCode()
                }
            }

            // Show banner with QR
            let currentPreferences = manager.getCategories()
            let bannerVC = BannerViewControllerTvOS(
                config: config,
                initialPreferences: currentPreferences,
                qrImage: qrImage,
                pairingCoordinator: coordinator,
                completion: { [weak self] preferences in
                    guard let self, let preferences else {
                        coordinator.stopPolling()
                        completion(nil)
                        return
                    }

                    // User manually saved via D-pad (QR timed out or user chose manual path)
                    coordinator.stopPolling()
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

            // Start polling
            coordinator.startPolling()
        }
    #endif
}
