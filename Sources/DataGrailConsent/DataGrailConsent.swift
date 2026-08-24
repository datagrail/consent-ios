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
        ///   - textStyleConfig: Optional font overrides for banner text elements
        ///   - completion: Called when user saves preferences or dismisses (nil if dismissed)
        public func showBanner(
            from presentingViewController: UIViewController,
            style: BannerDisplayStyle,
            textStyleConfig: BannerTextStyleConfig = BannerTextStyleConfig(),
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
                textStyleConfig: textStyleConfig,
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

// MARK: - Universal Consent

// In an extension, not the main class body, so the primary declaration stays inside
// SwiftLint's type_body_length limit. Same file: these call `manager` and
// `onConsentChangedCallback`, which are private and therefore file-scoped.
public extension DataGrailConsent {

    /// Register a user identifier and sync their consent across devices via the
    /// Universal Consent API.
    ///
    /// The SDK computes the user hash (`SHA-256(customerId:projectId:identifier)`), mints the
    /// timestamp and nonce, builds `stringToSign = "{customerId}:{userHash}:{timestamp}:{nonce}"`,
    /// and reconciles the device's live tracking signal on-device — but does NOT compute the
    /// HMAC. It invokes the customer-provided `getSignature` closure — which calls the
    /// customer's own backend — with that payload to obtain `{ signature, keyId }`, then
    /// attaches `X-DG-Signature`, `X-DG-Key-Id`, and the SDK's own `X-DG-Timestamp` /
    /// `X-DG-Nonce`. The shared secret never touches the device. Pass `nil` for `getSignature`
    /// to send a limited (API-key-only) write.
    ///
    /// Reads then writes. The read applies the tracking signal to LOCAL state; the write
    /// carries the user's RAW preferences. A device signal never changes what is stored
    /// cross-device — otherwise opening the app with ATT denied would erase a marketing
    /// opt-in the user made on the web, for every device on their identifier.
    /// - Parameters:
    ///   - identifier: The user identifier (email, account id, …). Normalized (NFC →
    ///     trim → lowercase) before hashing, so casing and stray whitespace cannot
    ///     split one user into multiple records.
    ///   - apiKey: Customer API key, sent as `X-DG-Api-Key` on every request so the
    ///     edge can resolve customer/tier/secret from KVS (required on writes to
    ///     locate the HMAC secret to verify).
    ///   - trackingSignal: The device's live tracking signal. Defaults to the current
    ///     App Tracking Transparency status, which the SDK reads from the OS — you do
    ///     not need to pass this. Override it only if your app manages ATT itself and
    ///     already holds the status. `denied` and `restricted` suppress non-essential
    ///     categories in the local state this call rehydrates; `authorized` and
    ///     `notDetermined` leave it untouched. A signal never enables a category, and
    ///     never affects what is written to the cross-device store.
    ///   - getSignature: Customer-provided signature provider (calls their backend). `nil`
    ///     selects limited (API-key-only) mode.
    ///   - completion: Completion handler with result.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    func setUserIdentifier(
        _ identifier: String,
        apiKey: String,
        trackingSignal: TrackingSignal = TrackingSignalReader.current(),
        getSignature: UniversalConsentSignatureProvider? = nil,
        completion: @escaping (Result<Void, ConsentError>) -> Void
    ) {
        guard let manager else {
            completion(.failure(.notInitialized))
            return
        }

        // READ then WRITE, matching the web SDK's setUserIdentifier flow. Rehydrating first
        // means the write persists the user's actual cross-device state rather than
        // clobbering a richer server-side record with whatever this fresh install happens to
        // hold locally.
        manager.rehydrateReturningRawPreferences(
            identifier,
            apiKey: apiKey,
            trackingSignal: trackingSignal
        ) { [weak self] rehydrateResult in
            switch rehydrateResult {
            case let .failure(error):
                // A read FAILURE is not a miss, and the two must not collapse. On failure we
                // cannot know whether local storage holds the user's raw choice or the
                // suppressed view a prior successful rehydrate persisted. Letting the write
                // fall back to getCategories() here could POST that suppressed view as the
                // user's raw cross-device choice — the exact corruption c525cec (TRUST-2491)
                // fixed on the write path — silently, since the write itself would succeed.
                // Surface the read failure instead; the caller can retry, and the user's real
                // choice stays in local storage to sync on a later successful call.
                DispatchQueue.main.async {
                    completion(.failure(error))
                }

            case let .success(rawPreferences):
                // The RAW preferences off the record on a hit, or nil on a GENUINE miss. On a
                // miss the getCategories() fallback in ConsentManager.setUserIdentifier is
                // safe: no prior rehydrate could have written a suppressed view for a user who
                // has no stored record.
                if rawPreferences != nil, let preferences = manager.getCategories() {
                    DispatchQueue.main.async {
                        self?.onConsentChangedCallback?(preferences)
                    }
                }

                manager.setUserIdentifier(
                    identifier,
                    apiKey: apiKey,
                    preferences: rawPreferences,
                    getSignature: getSignature
                ) { result in
                    DispatchQueue.main.async {
                        completion(result)
                    }
                }
            }
        }
    }

    /// Fetch a user's stored Universal Consent record without changing local state.
    ///
    /// Returns the record with signals already reconciled on-device (see
    /// ``setUserIdentifier(_:apiKey:trackingSignal:getSignature:completion:)`` for the
    /// read-then-write flow that also applies it locally). Use this when you want to inspect
    /// stored consent without touching the local store.
    ///
    /// - Parameters:
    ///   - identifier: The user identifier. Normalized (NFC → trim → lowercase) before hashing.
    ///   - apiKey: Customer API key, sent as `X-DG-Api-Key`.
    ///   - trackingSignal: This device's live signal. Defaults to the current ATT status.
    ///   - completion: Receives the reconciled record, or `nil` when no record is stored for
    ///     this user. `nil` means "no signal" — it is NOT an opt-out.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    func fetchUniversalConsent(
        _ identifier: String,
        apiKey: String,
        trackingSignal: TrackingSignal = TrackingSignalReader.current(),
        completion: @escaping (Result<UniversalConsentRecord?, ConsentError>) -> Void
    ) {
        guard let manager else {
            completion(.failure(.notInitialized))
            return
        }

        manager.fetchUniversalConsent(
            identifier,
            apiKey: apiKey,
            trackingSignal: trackingSignal
        ) { result in
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// Rehydrate local consent state from the Universal Consent store.
    ///
    /// Call this after ``initialize(configUrl:completion:)`` and BEFORE
    /// ``shouldDisplayBanner()`` when you know who the user is. When a stored record exists,
    /// its effective state is applied locally, so the banner does not re-prompt a user who
    /// already consented on another device.
    ///
    /// A read miss leaves local state untouched and writes nothing — "no record" is the
    /// absence of a signal, not a denial, so the banner still shows.
    ///
    /// - Parameter completion: `true` when local state was rehydrated from a stored record.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    func rehydrateFromUniversalConsent(
        _ identifier: String,
        apiKey: String,
        trackingSignal: TrackingSignal = TrackingSignalReader.current(),
        completion: @escaping (Result<Bool, ConsentError>) -> Void
    ) {
        guard let manager else {
            completion(.failure(.notInitialized))
            return
        }

        manager.rehydrateFromUniversalConsent(
            identifier,
            apiKey: apiKey,
            trackingSignal: trackingSignal
        ) { [weak self] result in
            if case .success(true) = result, let preferences = manager.getCategories() {
                DispatchQueue.main.async {
                    self?.onConsentChangedCallback?(preferences)
                }
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
}
