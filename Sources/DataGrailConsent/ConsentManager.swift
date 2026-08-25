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

    // MARK: - Universal Consent

    /// Register a user identifier and sync consent to the Universal Consent API.
    ///
    /// Uses the currently-loaded config (for `consentProjectId`, customer id, etc.) and the
    /// current stored preferences. The `getSignature` closure is customer-provided; the SDK
    /// never computes the HMAC and never holds the secret.
    ///
    /// Writes the RAW preferences. The tracking signal is deliberately not applied here — see
    /// ``ConsentService/setUserIdentifier(_:preferences:config:apiKey:getSignature:completion:)``
    /// for why suppressing before a write corrupts the cross-device record.
    ///
    /// - Parameters:
    ///   - identifier: The user identifier. Normalized (NFC → trim → lowercase) before
    ///     hashing, so casing and stray whitespace cannot split one user into
    ///     multiple records.
    ///   - apiKey: Customer API key, sent as `X-DG-Api-Key` on the write.
    ///   - preferences: Preferences to sync; defaults to the current stored preferences.
    ///     Callers that just rehydrated MUST pass the raw record explicitly, since
    ///     rehydration persists the reconciled view locally.
    ///   - getSignature: Customer-provided signature provider. `nil` selects limited
    ///     (API-key-only) mode.
    ///   - completion: Completion handler with result.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    public func setUserIdentifier(
        _ identifier: String,
        apiKey: String,
        preferences: ConsentPreferences? = nil,
        getSignature: UniversalConsentSignatureProvider? = nil,
        completion: @escaping (Result<Void, ConsentError>) -> Void
    ) {
        guard let config = currentConfig else {
            completion(.failure(.notInitialized))
            return
        }

        // Never fall back to getCategories(): its default (isCustomised: false) would POST a
        // fabricated choice for a user who never saw the banner, and any found record makes
        // rehydrate treat that identifier as answered — the banner would never show again.
        // Only an explicitly passed value or a real stored choice may be synced.
        guard let prefs = preferences ?? storage.loadPreferences() else {
            completion(.failure(.invalidConfiguration(
                "No consent preferences to sync — pass preferences or record a choice first"
            )))
            return
        }

        consentService.setUserIdentifier(
            identifier,
            preferences: prefs,
            config: config,
            apiKey: apiKey,
            getSignature: getSignature,
            completion: completion
        )
    }

    /// Fetch a user's stored Universal Consent record and reconcile signals on-device.
    ///
    /// The server returns raw, unreconciled data. This applies mandatory client-side
    /// reconciliation before returning: when an opt-out signal applies, every non-essential
    /// category is forced off regardless of the stored value. Essential categories survive.
    ///
    /// Two signals are considered and the more privacy-protective wins:
    /// - the record's stored `gpc`, recorded on the web where GPC exists; and
    /// - `trackingSignal`, this device's live ATT status.
    ///
    /// - Parameters:
    ///   - identifier: The user identifier. Normalized before hashing.
    ///   - apiKey: Customer API key, sent as `X-DG-Api-Key`.
    ///   - trackingSignal: This device's live signal. Defaults to the current ATT status.
    ///   - completion: Receives the reconciled record, or `nil` when no record exists.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    public func fetchUniversalConsent(
        _ identifier: String,
        apiKey: String,
        trackingSignal: TrackingSignal = TrackingSignalReader.current(),
        completion: @escaping (Result<UniversalConsentRecord?, ConsentError>) -> Void
    ) {
        guard let config = currentConfig else {
            completion(.failure(.notInitialized))
            return
        }

        // Capture the essential categories up front so reconciliation needs no `self` in the
        // completion. A `[weak self]` that deallocated mid-flight (e.g. a re-initialize on
        // logout/login while this fetch is in flight) used to fall through to returning the
        // RAW, unreconciled record — skipping ATT/GPC/CCPA suppression entirely.
        let essentialCategoryKeys = Set(getEssentialCategories())
        consentService.getUniversalConsent(
            identifier,
            config: config,
            apiKey: apiKey
        ) { result in
            switch result {
            case let .success(record):
                guard let record, let prefs = record.consentPreferences else {
                    completion(.success(record))
                    return
                }
                let reconciled = ConsentService.reconciledCookieOptions(
                    record: record,
                    rawCookieOptions: prefs.cookieOptions,
                    trackingSignal: trackingSignal,
                    essentialCategoryKeys: essentialCategoryKeys
                )
                completion(.success(record.withCookieOptions(reconciled)))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    /// Rehydrate local consent state from the Universal Consent store.
    ///
    /// Fetches the record for `identifier`, reconciles it, and — when one exists — persists
    /// the effective state locally so ``shouldDisplayBanner()``, ``getCategories()``, and
    /// ``isCategoryEnabled(_:)`` all reflect the consent the user gave on another device.
    /// This is the read half of Universal Consent: without it a web opt-in is invisible to
    /// the app and the banner reappears for a user who already answered it.
    ///
    /// A read MISS writes nothing. "No record" is the absence of a signal, not a denial, so
    /// persisting an empty record would both fabricate a choice the user never made and
    /// suppress the banner that should collect it.
    ///
    /// - Parameter completion: `true` when local state was rehydrated from a stored record.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    public func rehydrateFromUniversalConsent(
        _ identifier: String,
        apiKey: String,
        trackingSignal: TrackingSignal = TrackingSignalReader.current(),
        completion: @escaping (Result<Bool, ConsentError>) -> Void
    ) {
        rehydrateReturningRawPreferences(
            identifier,
            apiKey: apiKey,
            trackingSignal: trackingSignal
        ) { result in
            completion(result.map { $0 != nil })
        }
    }

    /// Rehydrate, and hand back the RAW stored preferences from the record.
    ///
    /// Same behavior as ``rehydrateFromUniversalConsent(_:apiKey:trackingSignal:completion:)``,
    /// except the completion carries the record's raw preferences (or `nil` on a miss) rather
    /// than a Bool. The read-then-write entry point needs this: rehydration persists the
    /// RECONCILED view locally, so a subsequent write that sourced its payload from
    /// ``getCategories()`` would read back the suppressed state and persist it to the store as
    /// though the user had chosen it. Returning the raw record lets the write carry what the
    /// user actually consented to.
    ///
    /// Deliberately a separate name rather than an overload — one distinguished only by its
    /// completion type is ambiguous at every call site that does not annotate the closure.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    func rehydrateReturningRawPreferences(
        _ identifier: String,
        apiKey: String,
        trackingSignal: TrackingSignal = TrackingSignalReader.current(),
        completion: @escaping (Result<ConsentPreferences?, ConsentError>) -> Void
    ) {
        guard let config = currentConfig else {
            completion(.failure(.notInitialized))
            return
        }

        // Goes to the service directly rather than through fetchUniversalConsent, which
        // returns an already-reconciled record. Both views are needed here: the reconciled
        // one to persist locally, the raw one to hand back for the write.
        consentService.getUniversalConsent(
            identifier,
            config: config,
            apiKey: apiKey
        ) { [weak self] result in
            switch result {
            case let .success(record):
                guard let self else {
                    completion(.success(nil))
                    return
                }
                // A miss (no record) writes nothing. A FOUND record is authoritative even when
                // its cookieOptions map is present-but-empty (answered with zero non-essential
                // categories) — treating that as a miss would re-prompt a user who already
                // answered, diverging from fetchUniversalConsent which counts it as found.
                guard let record else {
                    completion(.success(nil))
                    return
                }
                let rawCookieOptions = record.consentPreferences?.cookieOptions ?? [:]

                let raw = ConsentPreferences(
                    // A record that came back at all represents an answered prompt, so the
                    // rehydrated state is customised even if the writer left the flag false.
                    // shouldDisplayBanner() keys off stored preferences existing, and a
                    // non-customised record would re-prompt a user who already answered.
                    isCustomised: true,
                    cookieOptions: rawCookieOptions.map { CategoryConsent(gtmKey: $0.key, isEnabled: $0.value) }
                )

                // Local state gets the RECONCILED view — the suppress+reconcile sequence is
                // shared with fetchUniversalConsent via ConsentService.reconciledCookieOptions
                // so the two read paths cannot diverge.
                let reconciled = ConsentService.reconciledCookieOptions(
                    record: record,
                    rawCookieOptions: rawCookieOptions,
                    trackingSignal: trackingSignal,
                    essentialCategoryKeys: Set(self.getEssentialCategories())
                )
                let effective = ConsentPreferences(
                    isCustomised: true,
                    cookieOptions: reconciled.map { CategoryConsent(gtmKey: $0.key, isEnabled: $0.value) }
                )

                do {
                    try self.storage.savePreferences(effective)
                    // Stamp the CURRENT config version, not the record's. This marks the
                    // rehydrated consent as current for the config the app is running, which
                    // is what shouldDisplayBanner() compares against; carrying over a stale
                    // version from the writing device would re-prompt immediately.
                    if let version = self.currentConfig?.version {
                        self.storage.saveConfigVersion(version)
                    }
                    completion(.success(raw))
                } catch let error as ConsentError {
                    completion(.failure(error))
                } catch {
                    completion(.failure(.storageError(error.localizedDescription)))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
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
