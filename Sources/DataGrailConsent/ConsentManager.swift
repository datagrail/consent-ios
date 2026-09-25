import Foundation

/// Manages consent state and coordinates between storage, network, and configuration
public class ConsentManager {
    private let storage: ConsentStorage
    private let configService: ConfigService
    private let consentService: ConsentService
    private var currentConfig: ConsentConfig?
    /// In-memory only (never persisted): the identity and credentials of the last successful
    /// ``syncUserIdentifier``, so ``setCcpaOptout(_:completion:)`` can write through (TRUST-2591).
    var universalConsentSession: UniversalConsentSession?

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

    /// Get list of essential/always-on category GTM keys from config.
    ///
    /// Essential = `alwaysOn` OR the `gtmKey` contains the substring `"essential"`
    /// (case-insensitive). This is the agreed cross-SDK essential definition — consent-android
    /// unified on the identical predicate in `ConsentConfig.essentialCategoryKeys()`, so the two
    /// SDKs classify the same categories as essential.
    ///
    /// Correctness note: this set is now load-bearing for suppression, not just the banner.
    /// ``ConsentService/reconcile(cookieOptions:suppress:essentialCategoryKeys:)`` treats every
    /// key NOT in this set as suppressible by an opt-out signal (ATT/GPC/CCPA), so a genuinely
    /// essential category missed here would be wrongly forced off on read. The heuristic is
    /// therefore deliberately broad — both `alwaysOn` and the name-substring fallback contribute,
    /// across BOTH the layer categories and `initialCategories.initial`. A strictly-necessary
    /// category that carries neither `always_on: true` nor "essential" in its gtmKey (e.g.
    /// `dg-category-necessary`) is not detectable from config shape alone and must be published
    /// with one of those markers to be protected.
    /// - Returns: Array of GTM keys for categories that are always enabled
    public func getEssentialCategories() -> [String] {
        guard let config = currentConfig else {
            return []
        }

        var essentialKeys: [String] = []

        // Layer categories: alwaysOn OR gtmKey contains "essential" (matches android).
        for (_, layer) in config.layout.consentLayers {
            for element in layer.elements where normalizeElementType(element.type) == "category" {
                guard let categories = element.consentLayerCategories else { continue }
                for category in categories
                where (category.alwaysOn || category.gtmKey.lowercased().contains("essential"))
                    && !essentialKeys.contains(category.gtmKey) {
                    essentialKeys.append(category.gtmKey)
                }
            }
        }

        // Also treat any initial category whose gtmKey contains "essential" as essential,
        // covering configs that declare the category only in initialCategories.initial.
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
            // The RAW local CCPA flag (TRUST-2591); the service applies the sync_optout gate.
            ccpaOptout: storage.loadCcpaOptout(),
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

    /// The rehydrate behind ``rehydrateReturningRawPreferences(_:apiKey:trackingSignal:completion:)``,
    /// additionally reporting whether the store held a record at all. `raw` alone cannot tell a
    /// GENUINE MISS from a signal-only found record (both carry no raw choice), and the
    /// read-then-write path must treat only a genuine miss as a login transition (TRUST-2902).
    ///
    /// `ccpaOptout` is the record's stored `ccpa_optout` (`false` on a miss or when absent). When the
    /// record's choice is applied, the local CCPA flag takes it too (TRUST-2591) — always on a login
    /// (`replacesLocal`), otherwise only with the `sync_optout` gate on: with the gate off the SDK
    /// never puts the choice on the record, so adopting it would erase a local-only setting.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    func rehydrateReportingFound(
        _ identifier: String,
        apiKey: String,
        trackingSignal: TrackingSignal,
        replacesLocal: Bool = false,
        completion: @escaping (Result<RehydrateOutcome, ConsentError>) -> Void
    ) {
        guard let config = currentConfig else {
            completion(.failure(.notInitialized))
            return
        }

        // Capture storage, the essential categories, and the current config version up front
        // so the completion needs no `self`. A `[weak self]` deallocated mid-flight (e.g. a
        // re-initialize on logout/login while this fetch is in flight) must not silently skip
        // persisting or fall through to unreconciled state — the same hazard fetchUniversalConsent
        // was rewritten to avoid.
        let storage = self.storage
        let essentialCategoryKeys = Set(getEssentialCategories())
        let currentVersion = config.version
        let adoptsCcpaOptout = replacesLocal || config.universalConsent?.syncOptout == true

        // Goes to the service directly rather than through fetchUniversalConsent, which
        // returns an already-reconciled record. Both views are needed here: the reconciled
        // one to persist locally, the raw one to hand back for the write.
        consentService.getUniversalConsent(
            identifier,
            config: config,
            apiKey: apiKey
        ) { result in
            switch result {
            case let .success(record):
                // A miss (no record) writes nothing. A FOUND record is authoritative even when
                // its cookieOptions map is present-but-empty (answered with zero non-essential
                // categories) — treating that as a miss would re-prompt a user who already
                // answered, diverging from fetchUniversalConsent which counts it as found.
                guard let record else {
                    completion(.success(RehydrateOutcome(found: false, raw: nil, ccpaOptout: false)))
                    return
                }
                // A signal-only record (a gpc/ccpa signal on file, but consentPreferences nil)
                // is NOT an answered prompt: the user never chose. Fabricating isCustomised:true
                // with an empty map would suppress the banner forever AND read every category —
                // including always-on essential — as disabled for a user who never answered.
                // Leave local state untouched so the banner still shows, and return nil (no raw
                // choice to write back). Mirrors fetchUniversalConsent, which returns the record
                // unreconciled when consentPreferences is nil.
                guard let storedPrefs = record.consentPreferences else {
                    completion(.success(RehydrateOutcome(found: true, raw: nil, ccpaOptout: record.ccpaOptout)))
                    return
                }
                let rawCookieOptions = storedPrefs.cookieOptions

                let raw = ConsentPreferences(
                    // A record with stored preferences represents an answered prompt, so the
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
                    essentialCategoryKeys: essentialCategoryKeys
                )
                let effective = ConsentPreferences(
                    isCustomised: true,
                    cookieOptions: reconciled.map { CategoryConsent(gtmKey: $0.key, isEnabled: $0.value) }
                )

                do {
                    try storage.savePreferences(effective)
                    // Stamp the CURRENT config version, not the record's. This marks the
                    // rehydrated consent as current for the config the app is running, which
                    // is what shouldDisplayBanner() compares against; carrying over a stale
                    // version from the writing device would re-prompt immediately.
                    storage.saveConfigVersion(currentVersion)
                    // The record is authoritative for the stored CCPA choice (an absent field
                    // decodes to false). Not derived from anything: the user's recorded DNSMPI choice.
                    if adoptsCcpaOptout {
                        storage.saveCcpaOptout(record.ccpaOptout)
                    }
                    completion(.success(RehydrateOutcome(found: true, raw: raw, ccpaOptout: record.ccpaOptout)))
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
        universalConsentSession = nil
    }
}

// MARK: - Universal Consent read-then-write coordination

// In an extension (not the class body) so the coordinator stays within SwiftLint's
// type_body_length limit, matching how the public adapter splits its own UC surface.
extension ConsentManager {

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
        rehydrateReportingFound(
            identifier,
            apiKey: apiKey,
            trackingSignal: trackingSignal
        ) { result in
            completion(result.map(\.raw))
        }
    }

    /// Read-then-write coordination behind
    /// ``DataGrailConsent/setUserIdentifier(_:apiKey:trackingSignal:getSignature:completion:)``.
    ///
    /// Rehydrates any stored record onto local state FIRST (so a choice made on the web or
    /// another device is honored locally), then decides whether to write. The local choice is
    /// captured from storage BEFORE the rehydrate persists the signal-reconciled view, so any
    /// write carries the RAW choice and no device signal (ATT/GPC) leaks into the cross-device
    /// store. It never re-POSTs the record it just fetched.
    ///
    /// Which case applies depends on the persisted identity binding (TRUST-2902):
    ///
    /// - LOGIN (the device is unbound, or bound to a different identity):
    ///   - FOUND record: the record wins. It REPLACES local state — each category it carries takes
    ///     its reconciled value, each category it omits takes the neutral value, never the prior
    ///     local one — and nothing from the device is written, even when the device holds a
    ///     pre-login choice. A found record carrying no choice (signal-only) drops any stored
    ///     local state to neutral instead.
    ///   - MISS with an EXPLICIT local choice: that choice seeds the new identity's record.
    ///     Explicit means a stored choice (`loadPreferences() != nil` — only a user save or a
    ///     rehydrate ever writes it; initialize never seeds it) recorded while the device was not
    ///     bound to a DIFFERENT identity. State left behind by another bound identity belongs to
    ///     that identity (it may be their rehydrated record), so it is never explicit here.
    ///   - MISS without an explicit choice: nothing is written and the call succeeds. If another
    ///     identity's state is stored, local state returns to neutral (as ``clearUserIdentifier()``
    ///     does) so it does not linger; otherwise local state is left as it is.
    /// - RE-SYNC (already bound to this identity, so local changes are post-login): sync-on-change
    ///   as before — a found record is adopted and a GENUINE local change is written through
    ///   (an unchanged choice is not re-POSTed); on a miss the local choice seeds the record.
    ///
    /// With no local choice to write, the call succeeds without writing — it never fabricates a
    /// default. A read FAILURE does NOT write (overwriting a record we could not read would erase
    /// the user's real cross-device choice) and leaves the binding unchanged. Otherwise the
    /// binding is set once the call succeeds, so a failed write is still a login on retry.
    ///
    /// - Parameter onRehydrated: Invoked with the effective local preferences exactly when this
    ///   call rewrote local state — a record was adopted, or local state returned to neutral —
    ///   and never for a no-op, so the adapter can fire its consent-changed listener.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    func syncUserIdentifier(
        _ identifier: String,
        apiKey: String,
        trackingSignal: TrackingSignal = TrackingSignalReader.current(),
        getSignature: UniversalConsentSignatureProvider? = nil,
        onRehydrated: ((ConsentPreferences) -> Void)? = nil,
        completion: @escaping (Result<Void, ConsentError>) -> Void
    ) {
        // Capture the user's RAW local choice BEFORE rehydrate overwrites storage with the
        // signal-reconciled view. nil means the user has recorded no local choice yet.
        let localChoice = storage.loadPreferences()
        // nil when the preconditions fail — the read below fails on the same validation, so
        // no branch that binds is reachable without a hash.
        let userHash = currentConfig.flatMap {
            try? ConsentService.validatedUserHash(identifier: identifier, config: $0)
        }
        let bound = storage.loadBoundUserHash()
        let binding = LoginBinding(
            isResync: userHash != nil && bound == userHash,
            boundToOther: bound != nil && bound != userHash
        )
        // The RAW local CCPA flag, captured for the same reason: the rehydrate may adopt the
        // record's value (TRUST-2591).
        let localCcpaOptout = storage.loadCcpaOptout()

        rehydrateReportingFound(
            identifier,
            apiKey: apiKey,
            trackingSignal: trackingSignal,
            // A LOGIN replaces local state with the record, the CCPA flag included.
            replacesLocal: !binding.isResync
        ) { [weak self] result in
            guard let self else {
                completion(.failure(.notInitialized))
                return
            }
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(outcome):
                // Bind only after the call succeeds, so a failed write never binds.
                let storage = self.storage
                let bindingCompletion: (Result<Void, ConsentError>) -> Void = { writeResult in
                    if case .success = writeResult, let userHash {
                        storage.saveBoundUserHash(userHash)
                        self.universalConsentSession = UniversalConsentSession(
                            userHash: userHash, identifier: identifier, apiKey: apiKey, getSignature: getSignature
                        )
                    }
                    completion(writeResult)
                }
                let write: (ConsentPreferences) -> Void = { preferences in
                    // The write carries the user's own CCPA flag, not a value the rehydrate adopted.
                    storage.saveCcpaOptout(localCcpaOptout)
                    self.setUserIdentifier(
                        identifier,
                        apiKey: apiKey,
                        preferences: preferences,
                        getSignature: getSignature,
                        completion: bindingCompletion
                    )
                }
                self.completeAdopt(outcome: outcome, binding: binding, onRehydrated: onRehydrated)
                // The choice this call may write: never another bound identity's leftover state.
                let explicitChoice = binding.boundToOther ? nil : localChoice
                if let explicitChoice, self.shouldWrite(explicitChoice, outcome: outcome, binding: binding) {
                    write(explicitChoice)
                    return
                }
                self.dropUnreplacedLoginState(
                    outcome: outcome,
                    binding: binding,
                    hadLocalChoice: localChoice != nil,
                    onRehydrated: onRehydrated
                )
                bindingCompletion(.success(()))
            }
        }
    }

    /// When the rehydrate adopted a record's choice: a LOGIN replaces local state with the record
    /// (it never merges with it), and the listener fires with the adopted state.
    private func completeAdopt(
        outcome: RehydrateOutcome,
        binding: LoginBinding,
        onRehydrated: ((ConsentPreferences) -> Void)?
    ) {
        guard outcome.raw != nil else { return }
        if !binding.isResync {
            fillOmittedCategoriesWithNeutral()
        }
        if let effective = getCategories() {
            onRehydrated?(effective)
        }
    }

    /// The no-write tail of ``syncUserIdentifier``. On a LOGIN, stored state the record did not
    /// replace (a miss over another identity's state, or a found record carrying no choice) is
    /// dropped to neutral; nothing stored means nothing to drop, so no rewrite and no listener.
    /// The CCPA flag follows the same rule (TRUST-2591): another identity's value never lingers,
    /// and a found signal-only record is still authoritative for it.
    private func dropUnreplacedLoginState(
        outcome: RehydrateOutcome,
        binding: LoginBinding,
        hadLocalChoice: Bool,
        onRehydrated: ((ConsentPreferences) -> Void)?
    ) {
        guard !binding.isResync else { return }
        if outcome.raw == nil, hadLocalChoice {
            returnToNeutral()
            if let effective = getCategories() {
                onRehydrated?(effective)
            }
        } else if binding.boundToOther, !outcome.found {
            storage.saveCcpaOptout(false)
        }
        if outcome.found, outcome.raw == nil {
            storage.saveCcpaOptout(outcome.ccpaOptout)
        }
    }

    /// What ``rehydrateReportingFound`` reports: whether a record exists, its RAW choice (`nil` on a
    /// miss or a signal-only record), and its stored `ccpa_optout` (`false` on a miss).
    struct RehydrateOutcome {
        let found: Bool
        let raw: ConsentPreferences?
        let ccpaOptout: Bool
    }

    /// The identity and credentials of the last successful ``syncUserIdentifier``. Memory only:
    /// the signature provider cannot be persisted, so after a relaunch ``setCcpaOptout(_:completion:)``
    /// stays local until the host calls `setUserIdentifier` again.
    struct UniversalConsentSession {
        let userHash: String
        let identifier: String
        let apiKey: String
        let getSignature: UniversalConsentSignatureProvider?
    }

    /// The persisted-binding facts ``syncUserIdentifier`` branches on, captured before the read.
    struct LoginBinding {
        /// Already bound to this identity: local changes are post-login.
        let isResync: Bool
        /// Bound to a DIFFERENT identity: local state is that identity's, not this one's.
        let boundToOther: Bool
    }

    /// Whether ``syncUserIdentifier`` writes `choice` (an explicit local choice) after the read.
    ///
    /// - Miss: yes — seed the first record from the explicit choice, on login and re-sync alike.
    /// - Found, login: no — the record wins and has already been adopted.
    /// - Found, re-sync: only a GENUINE change. Re-POSTing an unchanged snapshot echoes state the
    ///   edge holds and, because the server never merges, an equal-but-older snapshot could
    ///   clobber a record newer than this device knows. A signal-only record (no raw choice) has
    ///   nothing to compare against, so the choice is written through as before.
    ///
    /// NOTE (TRUST-2592): when a found record and a post-login local choice differ, deciding which
    /// side WINS a true cross-device conflict — a stale local snapshot vs. a newer remote answer —
    /// needs a provenance-aware, decision_ts-stamped merge the SDK does not hold and the store
    /// never performs; that reconciliation is the edge's job. Until then the change is written
    /// through (sync-on-change).
    private func shouldWrite(
        _ choice: ConsentPreferences,
        outcome: RehydrateOutcome,
        binding: LoginBinding
    ) -> Bool {
        guard outcome.found else { return true }
        guard binding.isResync else { return false }
        guard let raw = outcome.raw else { return true }
        return !Self.cookieOptionsMatch(choice, raw)
    }

    /// Clear the Universal Consent identity binding and return local consent to neutral.
    ///
    /// Backs ``DataGrailConsent/clearUserIdentifier()``. Non-destructive: no network call, the
    /// server-side record is untouched, and the unique id, config cache, config version, locale
    /// and pending queue are all kept. Idempotent. The local CCPA opt-out returns to `false`.
    ///
    /// - Returns: The now-effective (default) preferences, or `nil` when no config is loaded.
    @discardableResult
    public func clearUserIdentifier() -> ConsentPreferences? {
        storage.clearBoundUserHash()
        universalConsentSession = nil
        returnToNeutral()
        return getCategories()
    }

    /// Record the user's EXPLICIT CCPA/CPRA "Do Not Sell or Share My Personal Information" choice
    /// (TRUST-2591). Backs ``DataGrailConsent/setCcpaOptout(_:completion:)``.
    ///
    /// Persists the flag locally; it changes no category and fires no listener. It is written
    /// through — the stored local choice plus the new flag, via the same write
    /// ``syncUserIdentifier`` makes — only when Universal Consent is enabled, the customer's
    /// `sync_optout` gate is on, the device is bound to an identity that a `setUserIdentifier` call
    /// in this process succeeded for, and an explicit local choice is stored (config defaults are
    /// never seeded). Otherwise it stays local and rides the next Universal Consent write.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    public func setCcpaOptout(_ optedOut: Bool, completion: @escaping (Result<Void, ConsentError>) -> Void) {
        storage.saveCcpaOptout(optedOut)
        guard let universalConsent = currentConfig?.universalConsent,
              universalConsent.enabled, universalConsent.syncOptout,
              let session = universalConsentSession,
              session.userHash == storage.loadBoundUserHash(),
              let localChoice = storage.loadPreferences()
        else {
            completion(.success(()))
            return
        }
        setUserIdentifier(
            session.identifier,
            apiKey: session.apiKey,
            preferences: localChoice,
            getSignature: session.getSignature,
            completion: completion
        )
    }

    /// The user's explicit CCPA/CPRA "Do Not Sell or Share" choice as stored on this device;
    /// `false` (not opted out) when never set. There is no OS-level DNSMPI signal on iOS, so this
    /// is the only source (the host app's setter, or an adopted record).
    public func getCcpaOptout() -> Bool {
        storage.loadCcpaOptout()
    }

    /// Complete a record just adopted on a LOGIN so it REPLACES local state rather than merging:
    /// every configured category the record omits takes its neutral value — the one
    /// ``isCategoryEnabled(_:)`` reads with no stored choice (`initialCategories.initial`), with
    /// essential always on — instead of reading as disabled. The rehydrate already overwrote the
    /// stored choice, so no prior local value survives; this only fills the gaps.
    private func fillOmittedCategoriesWithNeutral() {
        guard let config = currentConfig, let adopted = storage.loadPreferences() else { return }
        let present = Set(adopted.cookieOptions.map(\.gtmKey))
        let essential = Set(getEssentialCategories())
        let initial = Set(config.initialCategories.initial)
        let filled = getAllCategoryKeys(config)
            .filter { !present.contains($0) }
            .sorted()
            .map { CategoryConsent(gtmKey: $0, isEnabled: essential.contains($0) || initial.contains($0)) }
        guard !filled.isEmpty else { return }
        do {
            try storage.savePreferences(ConsentPreferences(
                isCustomised: adopted.isCustomised,
                cookieOptions: adopted.cookieOptions + filled
            ))
        } catch {
            // Left unfilled, an omitted category reads as disabled — the more protective failure.
            Logger.error("Failed to fill omitted categories after login: \(error.localizedDescription)")
        }
    }

    /// Remove the stored explicit choice so reads fall through to the config default via the
    /// existing ``getCategories()`` / ``shouldDisplayBanner()`` no-choice path — exactly what a
    /// fresh install sees. Shared by logout and a login over another bound identity's state.
    private func returnToNeutral() {
        storage.removePreferences()
        // Neutral includes "not opted out": the CCPA choice belongs to the identity being dropped.
        storage.saveCcpaOptout(false)
    }

    /// Whether a local choice's cookieOptions equal a just-fetched record's, compared as an
    /// order-independent `{gtmKey: isEnabled}` map. Used by ``syncUserIdentifier`` to skip a
    /// redundant Universal Consent re-write when the local choice adds no genuine change over the
    /// record just adopted — only `cookieOptions` are compared, since that is the payload the
    /// write carries. A `nil` local choice is never a match (the caller handles the miss/adopt
    /// case separately).
    private static func cookieOptionsMatch(
        _ local: ConsentPreferences?,
        _ record: ConsentPreferences
    ) -> Bool {
        guard let local else { return false }
        return cookieOptionsMap(local) == cookieOptionsMap(record)
    }

    private static func cookieOptionsMap(_ prefs: ConsentPreferences) -> [String: Bool] {
        var map: [String: Bool] = [:]
        for option in prefs.cookieOptions {
            map[option.gtmKey] = option.isEnabled
        }
        return map
    }
}

// MARK: - Universal Consent API key resolution (TRUST-2603)

extension ConsentManager {
    /// Resolve the edge API key for a Universal Consent call: an explicit value passed by the host
    /// wins (existing integrations behave exactly as before); otherwise fall back to
    /// `universalConsent.apiKey` from config.json, which lets the key rotate server-side with no
    /// client release. Returns `nil` when neither is present, so the caller can fail fast. An empty
    /// string counts as absent at either source.
    static func resolveUniversalConsentApiKey(explicit: String?, in config: ConsentConfig?) -> String? {
        let candidate = explicit?.isEmpty == false ? explicit : config?.universalConsent?.apiKey
        return candidate?.isEmpty == false ? candidate : nil
    }
}
