import Foundation

/// Manages consent state and coordinates between storage, network, and configuration
public class ConsentManager {
    private let storage: ConsentStorage
    private let configService: ConfigService
    private let consentService: ConsentService
    private var currentConfig: ConsentConfig?
    /// In-memory only (never persisted): the identity and credentials of the last successful
    /// ``syncUserIdentifier``, so ``setCcpaOptout(_:completion:)`` can write through (TRUST-2591).
    /// What that sync left is persisted separately (``ConsentStorage/loadSyncState()``).
    var universalConsentSession: UniversalConsentSession?

    /// Serializes logout/reset against an in-flight ``syncUserIdentifier`` so a login whose
    /// network round-trip outlives a logout cannot persist, notify, write, or rebind after it.
    fileprivate let identityGate = IdentityGate()

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
        // The persisted sync state only describes the identity it was recorded for.
        if let state = storage.loadSyncState(), state.userHash != storage.loadBoundUserHash() {
            storage.clearSyncState()
        }
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
            // Save locally. The user's own choice now replaces what the last sync left: the next
            // re-sync writes it, and a setCcpaOptout write-through sends it rather than the record's
            // raw choice. One critical section with the revision bump, so a rehydrate persisting
            // concurrently either precedes this save or follows it, never splits it.
            try identityGate.recordPreferencesSave {
                try storage.savePreferences(preferences)
                // When the user made this choice (TRUST-3223): a re-sync writes it through over a
                // found record only if it is newer than the record's latest decision.
                storage.saveDecisionTs()
                storage.saveConfigVersion(config.version)
                storage.clearSyncState()
            }

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
        writeUniversalConsent(
            identifier,
            apiKey: apiKey,
            preferences: preferences,
            decisionTs: nil,
            getSignature: getSignature,
            completion: completion
        )
    }

    /// ``setUserIdentifier(_:apiKey:preferences:getSignature:completion:)`` with the time the choice
    /// being written was made (unix seconds, TRUST-3223). `nil` uses the stored choice's time when
    /// `preferences` is `nil`, and otherwise sends none (the edge then uses the request time).
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    func writeUniversalConsent(
        _ identifier: String,
        apiKey: String,
        preferences: ConsentPreferences?,
        decisionTs: Int64?,
        ccpaOnly: Bool = false,
        ccpaOptout: Bool? = nil,
        getSignature: UniversalConsentSignatureProvider?,
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
            // The RAW local CCPA flag (TRUST-2591), or the one the caller captured; the service applies
            // the sync_optout gate.
            ccpaOptout: ccpaOptout ?? storage.loadCcpaOptout(),
            // When the stored choice was made (TRUST-3223). A caller-supplied choice has no known
            // time, so the edge stamps it with the request time, as before.
            decisionTs: decisionTs ?? (preferences == nil ? storage.loadDecisionTs() : nil),
            ccpaOnly: ccpaOnly,
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
    /// When `identifier` is the identity the device is bound to, the persisted sync state is updated
    /// the same way a ``DataGrailConsent/setUserIdentifier(_:apiKey:trackingSignal:getSignature:completion:)``
    /// adopt updates it: the stored view becomes what the last sync left, and the record's RAW choice
    /// what the record holds. So a later re-sync or ``setCcpaOptout(_:completion:)`` never mistakes
    /// the ATT/GPC/`ccpa_optout`-suppressed view this stores for a user change and writes it over the
    /// user's cross-device opt-ins. For any other identity the sync state is cleared. A
    /// ``clearUserIdentifier()`` or ``reset()`` that lands during the read supersedes it: nothing is
    /// persisted and the call fails.
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

    // MARK: - Retry

    /// Retry any pending API requests
    /// - Parameter completion: Completion handler with (successCount, failureCount)
    public func retryPendingRequests(completion: @escaping (Int, Int) -> Void) {
        consentService.retryPendingRequests(completion: completion)
    }

    // MARK: - Reset

    /// Clear all consent data
    public func reset() {
        identityGate.invalidate {
            storage.clearAll()
            currentConfig = nil
            universalConsentSession = nil
        }
    }
}

// MARK: - Universal Consent read-then-write coordination

// In an extension (not the class body) so the coordinator stays within SwiftLint's
// type_body_length limit, matching how the public adapter splits its own UC surface.
extension ConsentManager {

    /// The rehydrate behind ``rehydrateReturningRawPreferences(_:apiKey:trackingSignal:completion:)``,
    /// additionally reporting whether the store held a record at all. `raw` alone cannot tell a
    /// GENUINE MISS from a signal-only found record (both carry no raw choice), and the
    /// read-then-write path must treat only a genuine miss as a login transition (TRUST-2902).
    ///
    /// `ccpaOptout` is the record's stored `ccpa_optout` (`false` on a miss or when absent). When the
    /// record's choice is applied, the local CCPA flag takes it too (TRUST-2591) — always on a login
    /// (`replacesLocal`), otherwise only with the `sync_optout` gate on: with the gate off the SDK
    /// never puts the choice on the record, so adopting it would erase a local-only setting. Off a
    /// login it is also not adopted while a bound choice has yet to reach the record
    /// (``ConsentStorage/loadCcpaWritePending()``).
    ///
    /// `recordsSyncState` is set by the standalone rehydrate, which has no later bind step: when it
    /// persists a record for the bound identity it records the sync state itself (see
    /// ``rehydrateFromUniversalConsent(_:apiKey:trackingSignal:completion:)``).
    ///
    /// `keepsLocal` is asked, inside the persist's critical section and before anything is stored,
    /// whether a found record carrying a choice is adopted at all. When it answers yes (a re-sync
    /// writing a local choice newer than the record, TRUST-3223, or any save that landed during the
    /// read), the record's preferences and decision time are NOT stored (its CCPA flag still is,
    /// unless a local CCPA choice is pending), so the local choice is never overwritten and put back, and a
    /// user save landing mid-sync cannot be undone by a restore. The outcome then has `keptLocal` set.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    func rehydrateReportingFound( // swiftlint:disable:this function_body_length
        _ identifier: String,
        apiKey: String,
        trackingSignal: TrackingSignal,
        replacesLocal: Bool = false,
        snapshot: IdentityGate.Snapshot? = nil,
        recordsSyncState: Bool = false,
        keepsLocal: ((RehydrateOutcome) -> Bool)? = nil,
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
        let identityGate = self.identityGate
        let essentialCategoryKeys = Set(getEssentialCategories())
        let currentVersion = config.version
        let adoptsCcpaOptout = replacesLocal || config.universalConsent?.syncOptout == true
        // nil when the preconditions fail; the read below fails on the same validation.
        let userHash = try? ConsentService.validatedUserHash(identifier: identifier, config: config)

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

                var outcome = RehydrateOutcome(
                    found: true,
                    raw: raw,
                    ccpaOptout: record.ccpaOptout,
                    recordDecisionTs: record.updatedAtSeconds
                )
                do {
                    // With a `snapshot`, persist only if no logout landed mid-read: the check and the
                    // write are one critical section against the logout (and against a user save).
                    let persisted = try identityGate.ifCurrent(snapshot?.generation) {
                        // Decided before anything is stored, so a kept local choice is never touched.
                        // The CCPA flag is its own register: adopted on either path, keep-local included,
                        // so a category write-through never carries this device's stale flag over a
                        // newer CCPA choice made elsewhere. A setter call that landed mid-read is newer
                        // than the record, so it stays, and so does a bound choice that has not reached
                        // the record yet.
                        let adoptsRecordCcpa = adoptsCcpaOptout && !identityGate.ccpaChanged(since: snapshot)
                            && (replacesLocal || !storage.loadCcpaWritePending())
                        if keepsLocal?(outcome) == true {
                            // Nothing else is stored, the config version included: the kept choice
                            // keeps the version it was made under, so a config bump still re-prompts.
                            outcome.keptLocal = true
                            if adoptsRecordCcpa { storage.saveCcpaOptout(record.ccpaOptout) }
                            // The baseline the sync compares against: a kept choice that is then
                            // written counts as synced.
                            outcome.saveRevision = identityGate.preferencesSaveRevision
                            return
                        }
                        try storage.savePreferences(effective)
                        // The adopted choice was made when the record says, not now (TRUST-3223), so a
                        // later re-sync cannot mistake this copy for a change newer than the record.
                        if let recordDecisionTs = record.updatedAtSeconds {
                            storage.saveDecisionTs(recordDecisionTs)
                        } else {
                            storage.clearDecisionTs()
                        }
                        // Stamp the CURRENT config version, not the record's. This marks the
                        // rehydrated consent as current for the config the app is running, which
                        // is what shouldDisplayBanner() compares against; carrying over a stale
                        // version from the writing device would re-prompt immediately.
                        storage.saveConfigVersion(currentVersion)
                        // The record is authoritative for the stored CCPA choice (an absent field
                        // decodes to false). Not derived from anything: the user's recorded DNSMPI choice.
                        if adoptsRecordCcpa {
                            // Adopted with the record's time, as a category adopt is, so the next
                            // toggle here is stamped strictly after it (a tie keeps an opt-out).
                            storage.restoreCcpaChoice((record.ccpaOptout, record.updatedAtSeconds))
                        }
                        if recordsSyncState {
                            Self.recordStandaloneSyncState(
                                storage: storage,
                                userHash: userHash,
                                syncedLocal: effective,
                                syncedRaw: raw
                            )
                        }
                        // The user-save revision right after this persist: the baseline a sync compares
                        // against, since any save before it was overwritten here.
                        outcome.saveRevision = identityGate.preferencesSaveRevision
                    }
                    completion(persisted ? .success(outcome) : .failure(IdentityGate.superseded))
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

    /// The STANDALONE rehydrate behind ``rehydrateFromUniversalConsent(_:apiKey:trackingSignal:completion:)``:
    /// a read with no write and no bind step after it. The completion carries the record's RAW
    /// preferences (`nil` on a miss or a signal-only record) rather than a Bool, which is what the
    /// public method maps and what tests assert on.
    ///
    /// It RECORDS the persisted sync state (`recordsSyncState: true`): when the record is persisted
    /// for the identity the device is bound to, the stored view and the record's raw choice become
    /// that identity's last sync, exactly as an adopt by ``syncUserIdentifier`` leaves them; for any
    /// other identity the sync state is cleared. It records it inside the persist's critical section
    /// with no save-revision check, which is right only because nothing follows the persist.
    ///
    /// Not a building block for a read-then-write caller. A caller that writes or binds after the
    /// read must use ``rehydrateReportingFound`` (which records no sync state) and record the sync
    /// state itself once its write lands, as ``syncUserIdentifier`` does; reusing this would record
    /// sync state for a choice that write is about to replace.
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
            trackingSignal: trackingSignal,
            // Guards the persist against a logout landing mid-read, and keeps a setCcpaOptout call
            // made mid-read (it is newer than the record).
            snapshot: identityGate.snapshot,
            recordsSyncState: true
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
    /// - RE-SYNC (already bound to this identity): sync-on-change, decided on-device.
    ///   - The user changed nothing since the last sync (storage still holds what that sync left,
    ///     and no ``savePreferences(_:completion:)`` since, as recorded in the persisted sync state):
    ///     the record is adopted and NOTHING is written, found, missing or signal-only alike. What
    ///     the sync left is persisted, so this holds after an app relaunch too, and an
    ///     ATT/GPC-suppressed view is never written back.
    ///   - Otherwise the user changed something: the stored choice is written with the time it was
    ///     made (`decision_ts`, TRUST-3223), over a found record only when it was made after the
    ///     record's latest decision and its map differs; a stale choice adopts the record instead,
    ///     so it never undoes a newer revocation made elsewhere. On a miss it seeds the record.
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
        // Snapshot the identity generation BEFORE reading any state this login depends on, so the
        // guard is atomic with what it guards. A logout (clearUserIdentifier/reset) that lands at
        // any point after this snapshot bumps the generation; every later step then bails without
        // persisting, notifying, writing, or rebinding, so an in-flight login can't undo it.
        // Snapshotting after the reads below would leave a window where a logout clears storage but
        // this login still holds the stale pre-logout localChoice/binding and a post-logout
        // generation that passes every ifCurrent check — letting a superseded login seed-write the
        // old choice and rebind the just-cleared device.
        // The snapshot also records the setCcpaOptout revision, so a setter call made mid-flight
        // is recognized as newer than both the record and this pre-read capture (TRUST-2591).
        let snapshot = identityGate.snapshot
        // Capture the stored local choice BEFORE rehydrate overwrites storage with the
        // signal-reconciled view. nil means the user has recorded no local choice yet.
        let storedChoice = storage.loadPreferences()
        // nil when the preconditions fail — the read below fails on the same validation, so
        // no branch that binds is reachable without a hash.
        let userHash = currentConfig.flatMap {
            try? ConsentService.validatedUserHash(identifier: identifier, config: $0)
        }
        let bound = storage.loadBoundUserHash()
        let isResync = userHash != nil && bound == userHash
        let binding = LoginBinding(
            isResync: isResync,
            boundToOther: bound != nil && bound != userHash,
            unchangedSinceSync: isResync && unchangedSinceSync(storedChoice, userHash: userHash)
        )
        let localChoice = storedChoice
        // When that choice was made: written with it, and what decides whether it is newer than a
        // found record (TRUST-3223).
        let localDecisionTs = storage.loadDecisionTs()
        // The choice this call may write: never another bound identity's leftover state.
        let explicitChoice = binding.boundToOther ? nil : localChoice

        // Set by keepsLocal when it keeps the record out because a save landed during the read.
        var keptForSaveDuringRead = false
        rehydrateReportingFound(
            identifier,
            apiKey: apiKey,
            trackingSignal: trackingSignal,
            // A LOGIN replaces local state with the record, the CCPA flag included.
            replacesLocal: !binding.isResync,
            snapshot: snapshot,
            // A re-sync writing a local choice newer than the found record keeps it (TRUST-3223).
            keepsLocal: { [weak self] outcome in
                guard let self else { return false }
                // A save that landed during the read is the newest local choice: the record never
                // replaces it, whatever the pre-read choice was (it is written below instead).
                // Recorded here, in the persist's critical section, so the write decision below
                // follows exactly this one.
                if self.savedDuringRead(since: snapshot, binding: binding) {
                    keptForSaveDuringRead = true
                    return true
                }
                guard let explicitChoice else { return false }
                return self.shouldWrite(explicitChoice, decisionTs: localDecisionTs, outcome: outcome, binding: binding)
            },
            completion: { [weak self] result in
                guard let self else {
                    completion(.failure(.notInitialized))
                    return
                }
                switch result {
                case let .failure(error):
                    completion(.failure(error))
                case let .success(outcome):
                    self.applySyncOutcome(
                        outcome,
                        identifier: identifier,
                        apiKey: apiKey,
                        getSignature: getSignature,
                        hadLocalChoice: localChoice != nil,
                        keptForSaveDuringRead: keptForSaveDuringRead,
                        explicitChoice: explicitChoice,
                        localDecisionTs: localDecisionTs,
                        userHash: userHash,
                        binding: binding,
                        snapshot: snapshot,
                        onRehydrated: onRehydrated,
                        completion: completion
                    )
                }
            }
        )
    }

    /// Apply a successful read's outcome: adopt/complete a found record, seed-write an explicit
    /// unbound choice, or drop leftover state to neutral — then bind on success. Split out of
    /// ``syncUserIdentifier`` for readability and to keep each body within SwiftLint's limits.
    ///
    /// Guards against a logout that landed while the read (or a subsequent seed-write) was in
    /// flight: `snapshot` holds the identity generation captured before the read, and any change
    /// means a ``clearUserIdentifier()``/``reset()`` superseded this login, so it must not rebind
    /// or mutate storage.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    private func applySyncOutcome( // swiftlint:disable:this function_parameter_count
        _ outcome: RehydrateOutcome,
        identifier: String,
        apiKey: String,
        getSignature: UniversalConsentSignatureProvider?,
        hadLocalChoice: Bool,
        keptForSaveDuringRead: Bool,
        explicitChoice: ConsentPreferences?,
        localDecisionTs: Int64?,
        userHash: String?,
        binding: LoginBinding,
        snapshot: IdentityGate.Snapshot,
        onRehydrated: ((ConsentPreferences) -> Void)?,
        completion: @escaping (Result<Void, ConsentError>) -> Void
    ) {
        // Bind only after the call succeeds, so a failed write never binds. Rechecked because a
        // seed-write adds a second async hop a logout can land in. `syncedRaw` is the RAW choice
        // the record holds once this call is done: what was written, or the record just adopted.
        // `writtenCcpa` is the CCPA flag a write carried (`nil` when nothing was written). The stored
        // view is captured BEFORE any write is dispatched; the save revision it is checked against
        // is the one right after this call last wrote local state (the rehydrate's persist), or the
        // one at its start when it wrote none (a miss, or a kept local choice). So a save made during
        // the read or the write still reads as a user change, and one the persist overwrote does not.
        let saveRevision = outcome.saveRevision ?? snapshot.saveRevision
        let bindingCompletion: BindingCompletionFactory = { syncedRaw, writtenCcpa in
            let syncedLocal = self.storage.loadPreferences()
            return { [weak self] writeResult in
                guard let self else { return completion(writeResult) }
                let current = self.identityGate.ifCurrent(snapshot.generation) {
                    if case .success = writeResult, let userHash {
                        self.storage.saveBoundUserHash(userHash)
                        self.recordSyncState(
                            userHash: userHash,
                            syncedLocal: syncedLocal,
                            syncedRaw: syncedRaw,
                            saveRevision: saveRevision
                        )
                        self.resolveCcpaWritePending(writtenCcpa: writtenCcpa, snapshot: snapshot)
                        self.universalConsentSession = UniversalConsentSession(
                            userHash: userHash,
                            identifier: identifier,
                            apiKey: apiKey,
                            getSignature: getSignature
                        )
                    }
                }
                completion(current ? writeResult : .failure(IdentityGate.superseded))
            }
        }
        // Every local mutation, notification, and the decision to write run in one critical
        // section with the logout check, so a concurrent logout either fully precedes this (and
        // nothing happens) or fully follows it (and its own return-to-neutral wins).
        let current = identityGate.ifCurrent(snapshot.generation) {
            // A setCcpaOptout call that landed while the read was in flight is the newest choice:
            // it is already stored, nothing below overwrites it, and a write here carries it.
            let keepsStoredCcpa = identityGate.ccpaChanged(since: snapshot)
            dropPriorIdentityState(binding: binding, keepsStoredCcpa: keepsStoredCcpa)
            // A save that landed during the read replaced the pre-read choice: it is what is written,
            // with its own decision time, both read here in the same critical section. Over a found
            // record the rehydrate already decided that (keptForSaveDuringRead); only a miss, which
            // has no persist, is decided here.
            let savedDuringRead = writesMidReadSave(outcome, kept: keptForSaveDuringRead, snapshot, binding)
            let writeDecisionTs = savedDuringRead ? storage.loadDecisionTs() : localDecisionTs
            let writeChoice = adoptOrKeepLocal(
                savedDuringRead ? storage.loadPreferences() : explicitChoice,
                decisionTs: writeDecisionTs, outcome: outcome, binding: binding,
                writesRegardless: savedDuringRead, onRehydrated: onRehydrated
            )
            // The write carries the stored CCPA flag as it is now: the rehydrate adopted the record's
            // unless a local CCPA choice is pending (or landed mid-read), and the flag is its own
            // register, so a write never carries a stale value over a newer CCPA choice made elsewhere.
            let target = SyncTarget(
                identifier: identifier, apiKey: apiKey, getSignature: getSignature, userHash: userHash
            )
            if dispatchSyncWrite(
                writeChoice.map { SyncWrite($0, decisionTs: writeDecisionTs) },
                outcome: outcome, binding: binding, hadLocalChoice: hadLocalChoice,
                target: target, bindingCompletion: bindingCompletion
            ) {
                return
            }
            dropUnreplacedLoginState(
                outcome: outcome,
                binding: binding,
                hadLocalChoice: hadLocalChoice,
                keepsStoredCcpa: keepsStoredCcpa,
                onRehydrated: onRehydrated
            )
            // An unchanged re-sync that read no raw choice (a miss or a signal-only record) keeps
            // the raw choice the last sync recorded: local state is still the view built from it.
            let keptRaw = binding.unchangedSinceSync ? syncState(for: userHash)?.syncedRaw : nil
            bindingCompletion(outcome.raw ?? keptRaw, nil)(.success(()))
        }
        if !current {
            completion(.failure(IdentityGate.superseded))
        }
    }

    /// Builds the completion that binds a successful sync, from the RAW choice the record holds and
    /// the CCPA flag a write carried (`nil` when nothing was written).
    typealias BindingCompletionFactory = (ConsentPreferences?, Bool?) -> (Result<Void, ConsentError>) -> Void

    /// Before a sync applies its outcome: the other identity's sync state never describes this one,
    /// and a login replaces local state, so a CCPA write-pending marker from before it is dropped
    /// (unless a setter call landed during the read; that choice is kept).
    private func dropPriorIdentityState(binding: LoginBinding, keepsStoredCcpa: Bool) {
        if binding.boundToOther {
            storage.clearSyncState()
        }
        if !binding.isResync, !keepsStoredCcpa {
            storage.saveCcpaWritePending(false)
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
        // Not when a user save landed after the persist: local state is then the user's own choice,
        // not the record just adopted.
        if let saveRevision = outcome.saveRevision, identityGate.preferencesSaveRevision != saveRevision { return }
        if let effective = getCategories() {
            onRehydrated?(effective)
        }
    }

    /// Whether this sync writes a save that landed during its read: decided by the rehydrate for a
    /// found record (`kept`), here for a miss or a signal-only record, which have no persist.
    private func writesMidReadSave(
        _ outcome: RehydrateOutcome,
        kept: Bool,
        _ snapshot: IdentityGate.Snapshot,
        _ binding: LoginBinding
    ) -> Bool {
        if outcome.keptLocal { return kept }
        return outcome.raw == nil && savedDuringRead(since: snapshot, binding: binding)
    }

    /// Whether a user save landed on a RE-SYNC while its read was in flight. That save
    /// is the newest local choice: the record must not replace it, and the write carries it. A LOGIN
    /// replaces local state with the record regardless. Run inside the sync's critical section.
    private func savedDuringRead(since snapshot: IdentityGate.Snapshot, binding: LoginBinding) -> Bool {
        binding.isResync && identityGate.preferencesSaveRevision != snapshot.saveRevision
    }

    /// After the read: return `explicitChoice` if it is written, else adopt the record
    /// (``completeAdopt``). Over a found record carrying a choice the rehydrate already decided, before
    /// persisting anything (`keptLocal`, TRUST-3223): a kept local choice is still stored as it was, so
    /// local state is unchanged and no listener fires. Otherwise ``shouldWrite`` decides.
    ///
    /// `writesRegardless` (a save landed during the read) writes `explicitChoice` over a miss or a
    /// signal-only record without asking ``shouldWrite``: it is newer than anything the read saw.
    private func adoptOrKeepLocal(
        _ explicitChoice: ConsentPreferences?,
        decisionTs: Int64?,
        outcome: RehydrateOutcome,
        binding: LoginBinding,
        writesRegardless: Bool,
        onRehydrated: ((ConsentPreferences) -> Void)?
    ) -> ConsentPreferences? {
        if outcome.keptLocal {
            // A save equal to the record's raw choice changes nothing on the record.
            if writesRegardless, let raw = outcome.raw,
               Self.cookieOptionsMatch(explicitChoice, raw, neutral: neutralCategoryValues()) {
                return nil
            }
            return explicitChoice
        }
        completeAdopt(outcome: outcome, binding: binding, onRehydrated: onRehydrated)
        guard outcome.raw == nil else { return nil }
        if writesRegardless { return explicitChoice }
        return explicitChoice.flatMap {
            shouldWrite($0, decisionTs: decisionTs, outcome: outcome, binding: binding) ? $0 : nil
        }
    }

    /// The no-write tail of ``syncUserIdentifier``. On a LOGIN, stored state the record did not
    /// replace (a miss over another identity's state, or a found record carrying no choice) is
    /// dropped to neutral; nothing stored means nothing to drop, so no rewrite and no listener.
    /// The CCPA flag is resolved separately by ``loginCcpaOptout(outcome:binding:dropsChoice:)``.
    private func dropUnreplacedLoginState(
        outcome: RehydrateOutcome,
        binding: LoginBinding,
        hadLocalChoice: Bool,
        keepsStoredCcpa: Bool,
        onRehydrated: ((ConsentPreferences) -> Void)?
    ) {
        guard !binding.isResync else { return }
        let dropsChoice = outcome.raw == nil && hadLocalChoice
        if dropsChoice {
            storage.removePreferences()
        }
        let resolvedCcpa = Self.loginCcpaOptout(
            outcome: outcome,
            dropsChoice: dropsChoice,
            boundToOther: binding.boundToOther
        )
        if !keepsStoredCcpa, let resolvedCcpa {
            storage.saveCcpaOptout(resolvedCcpa)
        }
        if dropsChoice, let effective = getCategories() {
            onRehydrated?(effective)
        }
    }

    /// The CCPA flag a no-write LOGIN leaves stored (TRUST-2591), or `nil` to leave it as it is.
    ///
    /// - Found record: it is authoritative for the flag. A record carrying a choice already had
    ///   its flag adopted by the rehydrate (`nil` here); a signal-only record sets it here.
    /// - Miss: the flag returns to neutral (`false`) whenever the stored state is dropped or
    ///   belongs to another bound identity, so another identity's value never lingers.
    static func loginCcpaOptout(outcome: RehydrateOutcome, dropsChoice: Bool, boundToOther: Bool) -> Bool? {
        if outcome.found {
            return outcome.raw == nil ? outcome.ccpaOptout : nil
        }
        return dropsChoice || boundToOther ? false : nil
    }

    /// What ``rehydrateReportingFound`` reports: whether a record exists, its RAW choice (`nil` on a
    /// miss or a signal-only record), its stored `ccpa_optout` (`false` on a miss), the user-save
    /// revision right after it persisted the record locally (`nil` when it persisted nothing), the
    /// record's latest decision time, and whether it kept the local choice instead of storing the record.
    struct RehydrateOutcome {
        let found: Bool
        let raw: ConsentPreferences?
        let ccpaOptout: Bool
        var saveRevision: Int?
        /// The record's latest decision time (its `updated_at`, unix seconds); `nil` on a miss, a
        /// signal-only record, or when the record carries no usable `updated_at`.
        var recordDecisionTs: Int64?
        /// The found record's choice was not stored: a re-sync writes the newer local choice over it.
        var keptLocal = false
    }

    /// The standalone rehydrate just stored `syncedLocal`, the reconciled view of a record whose RAW
    /// choice is `syncedRaw`. For the bound identity that is exactly what an adopt by a sync leaves,
    /// so it is recorded the same way; otherwise the stored view no longer describes the bound
    /// identity's last sync, so its state is dropped. Runs inside the persist's critical section.
    static func recordStandaloneSyncState(
        storage: ConsentStorage,
        userHash: String?,
        syncedLocal: ConsentPreferences,
        syncedRaw: ConsentPreferences
    ) {
        guard let userHash, storage.loadBoundUserHash() == userHash else {
            storage.clearSyncState()
            return
        }
        storage.saveSyncState(UniversalConsentSyncState(
            userHash: userHash,
            syncedLocal: syncedLocal,
            syncedRaw: syncedRaw
        ))
    }

    /// The identity and credentials of the last successful ``syncUserIdentifier``. Memory only:
    /// the signature provider cannot be persisted, so after a relaunch ``setCcpaOptout(_:completion:)``
    /// stays local until the host calls `setUserIdentifier` again. What that sync left (the synced
    /// stored and raw choices) is persisted instead, see ``ConsentStorage/loadSyncState()``.
    ///
    /// Holding `getSignature` is what lets a later ``setCcpaOptout(_:completion:)`` sign its
    /// write-through, so the closure is retained until ``clearUserIdentifier()``, ``reset()`` or
    /// the next successful bind replaces it. The public API documents this so hosts capture weakly.
    struct UniversalConsentSession {
        let userHash: String
        let identifier: String
        let apiKey: String
        let getSignature: UniversalConsentSignatureProvider?
    }

    /// The persisted sync state for `userHash`, or `nil` when none is stored for it (none was
    /// recorded, the user saved a choice since, or it belongs to another identity).
    private func syncState(for userHash: String?) -> UniversalConsentSyncState? {
        guard let userHash, let state = storage.loadSyncState(), state.userHash == userHash else { return nil }
        return state
    }

    /// Whether the user changed nothing on this device since the last sync for `userHash`: storage
    /// still holds exactly what that sync left and no save happened since (a save clears the state).
    private func unchangedSinceSync(_ stored: ConsentPreferences?, userHash: String?) -> Bool {
        guard let stored, let syncedLocal = syncState(for: userHash)?.syncedLocal else { return false }
        return stored == syncedLocal
    }

    /// Persist what a sync left, unless the user saved a choice after `saveRevision` was captured:
    /// that save is a change the next re-sync must write, so no sync state is kept.
    private func recordSyncState(
        userHash: String,
        syncedLocal: ConsentPreferences?,
        syncedRaw: ConsentPreferences?,
        saveRevision: Int
    ) {
        guard identityGate.preferencesSaveRevision == saveRevision else {
            storage.clearSyncState()
            return
        }
        storage.saveSyncState(UniversalConsentSyncState(
            userHash: userHash,
            syncedLocal: syncedLocal,
            syncedRaw: syncedRaw
        ))
    }

    /// Settle the CCPA write-pending marker once a sync binds (TRUST-2591). A write that carried the
    /// stored flag put it on the record, so nothing is pending. A setter call that landed while the
    /// sync was in flight and that no write carried (on a first login it found the device unbound,
    /// so it was neither written through nor marked) is still waiting for the record, so it is marked
    /// pending: otherwise the next re-sync or rehydrate would adopt the record's older value over it.
    private func resolveCcpaWritePending(writtenCcpa: Bool?, snapshot: IdentityGate.Snapshot) {
        guard Self.syncsCcpaOptout(currentConfig) else { return }
        if let writtenCcpa, storage.loadCcpaOptout() == writtenCcpa {
            storage.saveCcpaWritePending(false)
        } else if identityGate.ccpaChanged(since: snapshot) {
            storage.saveCcpaWritePending(true)
        }
    }

    /// Whether a CCPA choice is written to the record at all: Universal Consent on and `sync_optout`.
    static func syncsCcpaOptout(_ config: ConsentConfig?) -> Bool {
        guard let universalConsent = config?.universalConsent else { return false }
        return universalConsent.enabled && universalConsent.syncOptout
    }

    /// The persisted-binding facts ``syncUserIdentifier`` branches on, captured before the read.
    struct LoginBinding {
        /// Already bound to this identity: local changes are post-login.
        let isResync: Bool
        /// Bound to a DIFFERENT identity: local state is that identity's, not this one's.
        let boundToOther: Bool
        /// A re-sync where the user changed nothing on this device since the last sync.
        let unchangedSinceSync: Bool
    }

    /// Whether ``syncUserIdentifier`` writes `choice` (an explicit local choice) after the read.
    ///
    /// - Re-sync with nothing changed on this device since the last sync: no, whatever the read
    ///   found. The record was adopted, and there is nothing of this device's to send.
    /// - Miss: yes — seed the first record from the explicit choice, on login and re-sync alike.
    /// - Found, login: no — the record wins and has already been adopted.
    /// - Found, re-sync after a local change: yes, if the change was made AFTER the record's latest
    ///   decision (TRUST-3223) and the map differs from the record's (otherwise nothing to send). A
    ///   local change that is not newer — a stale device returning after the user changed their
    ///   choice elsewhere — keeps the record the rehydrate adopted, so it can never undo a newer
    ///   revocation. A signal-only record (no raw choice) holds no category decision to undo, so the
    ///   choice is written; it carries its true decision time, so the edge's merge still ranks it.
    ///
    /// The write carries the choice's true `decision_ts` (when known), and the edge's per-category
    /// merge is last-writer-wins on it. A choice with no recorded time (stored before TRUST-3223) or
    /// a record with no usable `updated_at` cannot prove it is newer, so it is not written over a
    /// found record; neither is a same-second tie.
    private func shouldWrite(
        _ choice: ConsentPreferences,
        decisionTs: Int64?,
        outcome: RehydrateOutcome,
        binding: LoginBinding
    ) -> Bool {
        guard !binding.unchangedSinceSync else { return false }
        guard outcome.found else { return true }
        guard binding.isResync else { return false }
        guard let raw = outcome.raw else { return true }
        guard Self.isNewer(decisionTs, than: outcome.recordDecisionTs) else { return false }
        return !Self.cookieOptionsMatch(choice, raw, neutral: neutralCategoryValues())
    }

    /// The write a RE-SYNC that writes nothing else sends to flush a pending CCPA choice
    /// (``ConsentStorage/loadCcpaWritePending()``), or `nil` when there is none to flush.
    ///
    /// A bound CCPA choice that has not reached the record yet (a setter call after a relaunch, with
    /// no session to write through, or a failed write) is a local change too, and a re-sync is the
    /// first moment a session exists again. The write is CCPA-only (no category, isCustomised or record metadata): it sends no
    /// category, so the categories another device set stay as they are whatever the stamp. It is
    /// stamped with when the setter was called (``ConsentStorage/loadCcpaDecisionTs(now:)``), not
    /// the record's time, which would tie the record's `ccpa_optout` register (every write carries
    /// it, and a tie keeps the stored opt-out), and not the send time, which would let a late flush
    /// out-rank a newer CCPA choice made on another device meanwhile. Unknown, it sends no
    /// provenance (request time). It needs a found record that carries a choice (a miss or a signal-only
    /// record has nothing to flush over, and the setter never seeds config defaults) and an explicit
    /// local choice, as a setter write-through does. The stored flag is the pending value: the adopt
    /// does not replace it. Same rule as consent-android. No side effects: see ``dispatchSyncWrite``.
    private func pendingCcpaFlush(
        outcome: RehydrateOutcome,
        binding: LoginBinding,
        hadLocalChoice: Bool
    ) -> SyncWrite? {
        guard binding.isResync,
              hadLocalChoice,
              Self.syncsCcpaOptout(currentConfig),
              storage.loadCcpaWritePending(),
              let raw = outcome.raw
        else { return nil }
        return SyncWrite(preferences: raw, decisionTs: storage.loadCcpaDecisionTs(), syncedRaw: raw, ccpaOnly: true)
    }

    /// Where a sync's write goes: the identity and credentials it was called with.
    private struct SyncTarget {
        let identifier: String
        let apiKey: String
        let getSignature: UniversalConsentSignatureProvider?
        let userHash: String?
    }

    /// Send the sync's write, if any; `false` when nothing was dispatched and the sync goes on to its
    /// no-write tail. Runs inside the sync's critical section. The user's own choice (`explicit`)
    /// carries when they made it, so the edge ranks it by that and not by the send time; otherwise a
    /// pending CCPA choice may be flushed (``pendingCcpaFlush(outcome:binding:hadLocalChoice:)``):
    ///
    /// - A record that already holds the pending flag needs no signed write: the marker is cleared.
    /// - The adopt this re-sync just did is recorded as the sync state BEFORE the write, so a failed
    ///   flush still leaves the baseline matching what was stored (an ATT denial that suppressed a
    ///   category must not read as a user change on the retry).
    /// - A failed flush does not fail the sync: the read and adopt succeeded, so the identity binds
    ///   and the session is set as usual, and the flag stays pending for the next re-sync.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    private func dispatchSyncWrite(
        _ explicit: SyncWrite?,
        outcome: RehydrateOutcome,
        binding: LoginBinding,
        hadLocalChoice: Bool,
        target: SyncTarget,
        bindingCompletion: BindingCompletionFactory
    ) -> Bool {
        if let explicit {
            writeUniversalConsent(
                target.identifier,
                apiKey: target.apiKey,
                preferences: explicit.preferences,
                decisionTs: explicit.decisionTs,
                getSignature: target.getSignature,
                // The flag setUserIdentifier reads for the write, in this same critical section.
                completion: bindingCompletion(explicit.syncedRaw, storage.loadCcpaOptout())
            )
            return true
        }
        guard let write = pendingCcpaFlush(outcome: outcome, binding: binding, hadLocalChoice: hadLocalChoice)
        else { return false }
        let pendingFlag = storage.loadCcpaOptout()
        if outcome.ccpaOptout == pendingFlag {
            storage.saveCcpaWritePending(false)
            return false
        }
        if let userHash = target.userHash, let saveRevision = outcome.saveRevision {
            recordSyncState(
                userHash: userHash,
                syncedLocal: storage.loadPreferences(),
                syncedRaw: write.syncedRaw,
                saveRevision: saveRevision
            )
        }
        let carried = bindingCompletion(write.syncedRaw, pendingFlag)
        let notCarried = bindingCompletion(write.syncedRaw, nil)
        writeUniversalConsent(
            target.identifier,
            apiKey: target.apiKey,
            preferences: write.preferences,
            decisionTs: write.decisionTs,
            ccpaOnly: write.ccpaOnly,
            getSignature: target.getSignature
        ) { result in
            if case let .failure(error) = result {
                Logger.error("Pending CCPA choice not written; it stays pending: \(error.localizedDescription)")
                notCarried(.success(()))
            } else {
                carried(result)
            }
        }
        return true
    }

    /// The write a re-sync sends: the preferences, their decision time (`nil` lets the edge stamp
    /// the request time), and the raw choice the record holds once it lands.
    private struct SyncWrite {
        let preferences: ConsentPreferences
        let decisionTs: Int64?
        let syncedRaw: ConsentPreferences
        /// Sent as a CCPA-only write: `preferences` is not sent.
        let ccpaOnly: Bool

        /// A write of `choice` itself: the record holds it once it lands.
        init(_ choice: ConsentPreferences, decisionTs: Int64?) {
            self.init(preferences: choice, decisionTs: decisionTs, syncedRaw: choice, ccpaOnly: false)
        }

        init(preferences: ConsentPreferences, decisionTs: Int64?, syncedRaw: ConsentPreferences, ccpaOnly: Bool) {
            self.preferences = preferences
            self.decisionTs = decisionTs
            self.syncedRaw = syncedRaw
            self.ccpaOnly = ccpaOnly
        }
    }

    /// Whether a local choice made at `local` is strictly newer than a record whose latest decision
    /// is `record`. `updated_at` is the latest decision across ALL the record's registers, categories
    /// and record-level fields such as `ccpa_optout` alike, so this is a conservative bound (the read
    /// exposes no per-category times) that errs toward adopting.
    static func isNewer(_ local: Int64?, than record: Int64?) -> Bool {
        guard let local, let record else { return false }
        return local > record
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
        identityGate.invalidate {
            storage.clearBoundUserHash()
            universalConsentSession = nil
            returnToNeutral()
        }
        return getCategories()
    }

    /// Record the user's EXPLICIT CCPA/CPRA "Do Not Sell or Share My Personal Information" choice
    /// (TRUST-2591). Backs ``DataGrailConsent/setCcpaOptout(_:completion:)``.
    ///
    /// Persists the flag locally; it changes no category and fires no listener. It is written
    /// through — the user's RAW choice plus the new flag, via the same write
    /// ``syncUserIdentifier`` makes — only when Universal Consent is enabled, the customer's
    /// `sync_optout` gate is on, the device is bound to an identity that a `setUserIdentifier` call
    /// in this process succeeded for, and an explicit local choice is stored (config defaults are
    /// never seeded). Otherwise it stays local and rides the next Universal Consent write. While
    /// bound, the choice is marked pending (``ConsentStorage/loadCcpaWritePending()``) until a write
    /// carries it, so a re-sync or rehydrate does not replace it with the record's older value, and
    /// the next re-sync writes it as a CCPA-only write (see ``dispatchSyncWrite``). A write-through is
    /// CCPA-only too unless categories can ride along safely (see the comment in the body), so a
    /// possibly-suppressed local view is never sent as the user's choice.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    public func setCcpaOptout(_ optedOut: Bool, completion: @escaping (Result<Void, ConsentError>) -> Void) {
        // Storing the flag, checking the session, and dispatching the write run in one critical
        // section against logout/reset and an in-flight sync: a logout either precedes it (the
        // flag stays local) or follows it (the write for the still-bound identity is already in
        // flight, and the logout's return-to-neutral resets the local flag).
        var dispatched = false
        identityGate.recordCcpaChoice {
            storage.saveCcpaChoice(optedOut)
            // Bound: the choice is pending until a write carries it, so a re-sync or rehydrate keeps
            // it rather than adopting the record's older value (also when it cannot be written now).
            // Whatever the sync_optout gate (TRUST-3381, as consent-banner #756): a choice made with
            // the gate off is not sent, and the next re-sync after the gate turns on flushes it.
            if storage.loadBoundUserHash() != nil {
                storage.saveCcpaWritePending(true)
            }
            guard Self.syncsCcpaOptout(currentConfig),
                  let session = universalConsentSession,
                  session.userHash == storage.loadBoundUserHash(),
                  let localChoice = storage.loadPreferences()
            else { return }
            dispatched = true
            writeCcpaChoice(optedOut, localChoice: localChoice, session: session, completion: completion)
        }
        if !dispatched {
            completion(.success(()))
        }
    }

    /// The ``setCcpaOptout(_:completion:)`` write-through, dispatched inside its critical section.
    ///
    /// As consent-banner #756 (withCategories): an unsynced local category change with a known
    /// decision time goes first, in its own write at its own time, and is recorded as synced. The
    /// CCPA-only write that follows advances the record's `updated_at` (the latest decision over ALL
    /// registers), so without that first write the next re-sync would read the change as older than
    /// the record and adopt over it. Also when the last sync found no category choice, so the CCPA
    /// write never leaves an empty block. An unknown time is not sent stamped now (P0-06).
    ///
    /// Then the CCPA-only write (TRUST-2591 decision, 2026-10-26): the flag alone, dated when this
    /// CCPA choice was made, never the category map, so it cannot undo a newer revocation made
    /// elsewhere (TRUST-3311) and the CCPA register is not tied to a category time.
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    private func writeCcpaChoice(
        _ optedOut: Bool,
        localChoice: ConsentPreferences,
        session: UniversalConsentSession,
        completion: @escaping (Result<Void, ConsentError>) -> Void
    ) {
        let syncState = syncState(for: session.userHash)
        let choiceDecisionTs = storage.loadDecisionTs()
        let sendsCategories = choiceDecisionTs != nil
            && (!unchangedSinceSync(localChoice, userHash: session.userHash)
                || (syncState != nil && syncState?.syncedRaw == nil))
        let saveRevision = identityGate.preferencesSaveRevision
        // The flag and its time, captured together now: the CCPA-only write may go out after the
        // categories write, and must never carry a value a logout or another identity left meanwhile.
        let ccpaOptout = storage.loadCcpaOptout()
        let ccpaDecisionTs = storage.loadCcpaDecisionTs()
        let sendCcpa: () -> Void = { [weak self] in
            guard let self else { return completion(.failure(.notInitialized)) }
            self.writeUniversalConsent(
                session.identifier,
                apiKey: session.apiKey,
                preferences: localChoice,
                decisionTs: ccpaDecisionTs,
                ccpaOnly: true,
                ccpaOptout: ccpaOptout,
                getSignature: session.getSignature
            ) { [weak self] result in
                if case .success = result, let self {
                    // Reached the record. A newer toggle made during the write stays pending.
                    self.identityGate.ifCurrent(nil) {
                        if self.storage.loadCcpaOptout() == optedOut {
                            self.storage.saveCcpaWritePending(false)
                        }
                    }
                }
                completion(result)
            }
        }
        guard sendsCategories else { return sendCcpa() }
        writeUniversalConsent(
            session.identifier,
            apiKey: session.apiKey,
            preferences: localChoice,
            decisionTs: choiceDecisionTs,
            getSignature: session.getSignature
        ) { [weak self] result in
            guard let self, case .success = result else { return completion(result) }
            // The record now holds this choice, so the next re-sync must not send it again. Not over
            // a save made since, nor after a logout or a bind to another identity.
            // The binding check, the sync-state record and dispatching the CCPA-only write run in one
            // critical section: a logout or rebind either precedes it (nothing more is sent) or
            // follows it (the CCPA write for the still-bound identity is already in flight).
            var stillBound = false
            self.identityGate.ifCurrent(nil) {
                stillBound = self.storage.loadBoundUserHash() == session.userHash
                guard stillBound else { return }
                self.recordSyncState(
                    userHash: session.userHash,
                    syncedLocal: localChoice,
                    syncedRaw: localChoice,
                    saveRevision: saveRevision
                )
                sendCcpa()
            }
            if !stillBound {
                completion(.failure(IdentityGate.superseded))
            }
        }
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
        guard let adopted = storage.loadPreferences() else { return }
        let present = Set(adopted.cookieOptions.map(\.gtmKey))
        let filled = neutralCategoryValues()
            .filter { !present.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { CategoryConsent(gtmKey: $0.key, isEnabled: $0.value) }
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

    /// Every configured category's NEUTRAL value: what ``isCategoryEnabled(_:)`` reads with no
    /// stored choice (`initialCategories.initial`), with essential always on. Empty with no config.
    private func neutralCategoryValues() -> [String: Bool] {
        guard let config = currentConfig else { return [:] }
        let essential = Set(getEssentialCategories())
        let initial = Set(config.initialCategories.initial)
        var values: [String: Bool] = [:]
        for key in getAllCategoryKeys(config) {
            values[key] = essential.contains(key) || initial.contains(key)
        }
        return values
    }

    /// Remove the stored explicit choice so reads fall through to the config default via the
    /// existing ``getCategories()`` / ``shouldDisplayBanner()`` no-choice path — exactly what a
    /// fresh install sees. Used by logout; a login drops state via ``dropUnreplacedLoginState``.
    private func returnToNeutral() {
        storage.removePreferences()
        // Neutral includes "not opted out": the CCPA choice belongs to the identity being dropped.
        storage.saveCcpaOptout(false)
        storage.saveCcpaWritePending(false)
    }

    /// Whether a local choice's cookieOptions equal a just-fetched record's, compared as an
    /// order-independent `{gtmKey: isEnabled}` map. Used by ``syncUserIdentifier`` to skip a
    /// redundant Universal Consent re-write when the local choice adds no genuine change over the
    /// record just adopted — only `cookieOptions` are compared, since that is the payload the
    /// write carries. A `nil` local choice is never a match (the caller handles the miss/adopt
    /// case separately).
    ///
    /// A category the record omits matches when the local value is its `neutral` one: a LOGIN
    /// fills omitted categories with config defaults (``fillOmittedCategoriesWithNeutral()``),
    /// and those defaults are not a choice the user made, so they must not trigger a write that
    /// attributes them to the user. Changing such a category away from neutral is still a change.
    static func cookieOptionsMatch(
        _ local: ConsentPreferences?,
        _ record: ConsentPreferences,
        neutral: [String: Bool]
    ) -> Bool {
        guard let local else { return false }
        let localMap = cookieOptionsMap(local)
        let recordMap = cookieOptionsMap(record)
        guard Set(recordMap.keys).isSubset(of: localMap.keys) else { return false }
        return localMap.allSatisfy { key, isEnabled in
            if let recorded = recordMap[key] {
                return recorded == isEnabled
            }
            return neutral[key] == isEnabled
        }
    }

    private static func cookieOptionsMap(_ prefs: ConsentPreferences) -> [String: Bool] {
        var map: [String: Bool] = [:]
        for option in prefs.cookieOptions {
            map[option.gtmKey] = option.isEnabled
        }
        return map
    }
}

/// Serializes identity invalidation (logout/reset) against the steps of an in-flight
/// ``ConsentManager/syncUserIdentifier``: a monotonic generation plus a lock held across each
/// check-and-mutate, so a check can never pass and then be overtaken by a logout before the
/// mutation it guards. Recursive because a guarded step may complete synchronously into another
/// guarded step (a seed-write's completion binds) on the same thread.
///
/// A seed-write dispatched before a logout still reaches the network — that request is already
/// in flight — but the logout wins locally: the login never rebinds after it.
final class IdentityGate {
    static let superseded = ConsentError.validationError("User identifier sync superseded by logout")

    /// What a sync captures before its read: the identity generation, the revision of the host's
    /// ``ConsentManager/setCcpaOptout(_:completion:)`` calls (TRUST-2591), and the user-save
    /// revision, so a ``ConsentManager/savePreferences(_:completion:)`` made at any point after it
    /// (during the read included) counts as a user change (TRUST-2902).
    struct Snapshot {
        let generation: Int
        let ccpaRevision: Int
        let saveRevision: Int
    }

    private let lock = NSRecursiveLock()
    private var current = 0
    private var ccpaRevision = 0
    private var saveRevision = 0

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(generation: current, ccpaRevision: ccpaRevision, saveRevision: saveRevision)
    }

    /// Bump the CCPA revision and run `body` (the setter's own work) in the same critical section.
    func recordCcpaChoice(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        ccpaRevision &+= 1
        body()
    }

    /// Bump the user-save revision and run `body` (the save's own work, its storage write included)
    /// in the same critical section, so a save and a rehydrate's persist never interleave.
    func recordPreferencesSave(_ body: () throws -> Void) rethrows {
        lock.lock()
        defer { lock.unlock() }
        saveRevision &+= 1
        try body()
    }

    /// The current user-save revision. A sync records what it left as synced only if no
    /// ``ConsentManager/savePreferences(_:completion:)`` landed since it last wrote local state (or
    /// since it started, when it wrote none), so a save made during its read or its write still
    /// counts as a user change.
    var preferencesSaveRevision: Int {
        lock.lock()
        defer { lock.unlock() }
        return saveRevision
    }

    /// Whether a setter call landed since `snapshot` was taken; `false` for a `nil` snapshot.
    func ccpaChanged(since snapshot: Snapshot?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let snapshot else { return false }
        return snapshot.ccpaRevision != ccpaRevision
    }

    /// Bump the generation and run `body` (the logout's own mutations) in the same critical section.
    func invalidate(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        current &+= 1
        body()
    }

    /// Run `body` only if no invalidation happened since `generation` was captured; `nil` always runs.
    /// - Returns: Whether `body` ran.
    @discardableResult
    func ifCurrent(_ generation: Int?, _ body: () throws -> Void) rethrows -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let generation, generation != current { return false }
        try body()
        return true
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

    /// ``resolveUniversalConsentApiKey(explicit:in:)`` with the failure the public calls report.
    /// With no config loaded yet (``DataGrailConsent/initialize(configUrl:completion:)`` is still
    /// fetching it) the config fallback cannot be consulted, so that is `.notInitialized`, not a
    /// missing key.
    static func universalConsentApiKey(explicit: String?, in config: ConsentConfig?) -> Result<String, ConsentError> {
        if let key = resolveUniversalConsentApiKey(explicit: explicit, in: config) {
            return .success(key)
        }
        guard config != nil else { return .failure(.notInitialized) }
        return .failure(.validationError(
            "Universal Consent requires an API key: pass apiKey or set universalConsent.apiKey in config.json"
        ))
    }
}
