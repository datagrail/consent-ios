import Foundation

/// Handles local storage of consent data using UserDefaults
public class ConsentStorage {
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Keys {
        static let preferences = "datagrail_consent_preferences"
        static let uniqueId = "datagrail_consent_id"
        static let version = "datagrail_consent_version"
        static let localeCode = "datagrail_consent_locale_code"
        static let configCache = "datagrail_consent_config_cache"
        static let pendingEvents = "datagrail_consent_pending_events"
        static let boundUserHash = "datagrail_consent_bound_user_hash"
        static let ccpaOptout = "datagrail_consent_ccpa_optout"
        static let ccpaWritePending = "datagrail_consent_ccpa_write_pending"
        static let syncState = "datagrail_consent_sync_state"
        static let decisionTs = "datagrail_consent_decision_ts"
        static let ccpaDecisionTs = "datagrail_consent_ccpa_decision_ts"
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Preferences

    /// Save consent preferences to local storage
    /// - Parameter preferences: The consent preferences to save
    /// - Throws: ConsentError.storageError if encoding fails
    public func savePreferences(_ preferences: ConsentPreferences) throws {
        do {
            let data = try encoder.encode(preferences)
            userDefaults.set(data, forKey: Keys.preferences)
        } catch {
            throw ConsentError.storageError("Failed to encode preferences: \(error.localizedDescription)")
        }
    }

    /// Load consent preferences from local storage
    /// - Returns: The stored preferences, or nil if none exist
    public func loadPreferences() -> ConsentPreferences? {
        guard let data = userDefaults.data(forKey: Keys.preferences) else {
            return nil
        }
        return try? decoder.decode(ConsentPreferences.self, from: data)
    }

    /// Remove the stored consent preferences, returning the device to the no-choice state a
    /// fresh install has. Leaves every other key (unique id, config cache, version, locale,
    /// pending queue) intact — unlike ``clearAll()`` — except the decision time, which belongs
    /// to the choice being removed.
    public func removePreferences() {
        userDefaults.removeObject(forKey: Keys.preferences)
        clearDecisionTs()
    }

    // MARK: - Decision time (TRUST-3223)

    /// How far ahead of this device's clock a decision time may be before it is treated as bogus.
    /// Matches the edge's own future clamp (now + 300 s).
    static let decisionTsFutureToleranceSeconds: Int64 = 300

    /// How far ahead a STORED decision time may be and still be read back. A time adopted from a
    /// record can already sit at the edge's clamp, and the monotonic stamp of a choice made right
    /// after it has to land beyond it and still be readable, or that fresh choice would read as
    /// unknown and lose to the record it follows. Twice the edge clamp leaves that room, while a
    /// stamp written under a clock that has since been corrected is still rejected.
    static let decisionTsStoredToleranceSeconds: Int64 = 2 * decisionTsFutureToleranceSeconds

    /// Record WHEN the stored choice was made, as unix seconds. `nil` stamps a choice the user just
    /// made; an adopt passes the adopted record's time instead.
    ///
    /// The "now" stamp is MONOTONIC: never earlier than the previous stamp + 1 (unless that stamp
    /// is itself implausibly far ahead), so two choices in the same second, or a choice right after
    /// adopting a record stamped slightly ahead of this clock, still order correctly. That is the
    /// only clock-skew protection: decision times from different devices are compared as-is, so skew
    /// between devices (up to the edge's ~300 s bound) can still mis-order changes made that close
    /// together. Mirrors consent-banner `setDecisionTs` (TRUST-3154).
    func saveDecisionTs(_ decisionTs: Int64? = nil, now: Int64 = ConsentStorage.nowSeconds()) {
        let value: Int64
        if let decisionTs {
            value = decisionTs
        } else if let previous = loadDecisionTs(now: now) {
            // Capped at what loadDecisionTs reads back (only reachable by hundreds of same-second saves).
            value = min(max(now, previous + 1), now + Self.decisionTsStoredToleranceSeconds)
        } else {
            value = now
        }
        userDefaults.set(String(value), forKey: Keys.decisionTs)
    }

    /// When the stored choice was made, or `nil` when unknown: no choice is stored, it was stored
    /// before the SDK recorded decision times, or the stamp is more than
    /// ``decisionTsStoredToleranceSeconds`` ahead of this clock. A stamp that far ahead is bogus (the
    /// clock was ahead and has since been corrected); the edge restamps such a write to now + 300, so
    /// it would never repair itself and would out-rank every record forever.
    func loadDecisionTs(now: Int64 = ConsentStorage.nowSeconds()) -> Int64? {
        guard let raw = userDefaults.string(forKey: Keys.decisionTs),
              let value = Int64(raw), value >= 0
        else { return nil }
        return value <= now + Self.decisionTsStoredToleranceSeconds ? value : nil
    }

    /// The stored choice no longer has a known decision time.
    func clearDecisionTs() {
        userDefaults.removeObject(forKey: Keys.decisionTs)
    }

    /// Unix seconds, the resolution `decision_ts` has on the Universal Consent wire.
    static func nowSeconds() -> Int64 {
        Int64(Date().timeIntervalSince1970.rounded(.down))
    }

    // MARK: - Universal Consent identity binding

    /// Persist the user hash of the identity this device is bound to for Universal Consent.
    /// Only the hash is stored — never the raw identifier.
    public func saveBoundUserHash(_ userHash: String) {
        userDefaults.set(userHash, forKey: Keys.boundUserHash)
    }

    /// Load the user hash of the identity this device is bound to, or nil when unbound.
    public func loadBoundUserHash() -> String? {
        userDefaults.string(forKey: Keys.boundUserHash)
    }

    /// Clear the Universal Consent identity binding, and the sync state that belongs to it.
    public func clearBoundUserHash() {
        userDefaults.removeObject(forKey: Keys.boundUserHash)
        clearSyncState()
    }

    /// Persist what the last successful Universal Consent sync left for the bound identity, so a
    /// re-sync after an app relaunch can still tell whether the user changed anything since.
    /// Holds consent maps and the user hash only, never the raw identifier.
    func saveSyncState(_ state: UniversalConsentSyncState) {
        guard let data = try? encoder.encode(state) else {
            // Without it the next re-sync treats the stored choice as a change and writes it.
            clearSyncState()
            return
        }
        userDefaults.set(data, forKey: Keys.syncState)
    }

    /// The persisted sync state, or nil when none is stored.
    func loadSyncState() -> UniversalConsentSyncState? {
        guard let data = userDefaults.data(forKey: Keys.syncState) else { return nil }
        return try? decoder.decode(UniversalConsentSyncState.self, from: data)
    }

    /// Forget the persisted sync state: the next re-sync treats the stored choice as a user change.
    func clearSyncState() {
        userDefaults.removeObject(forKey: Keys.syncState)
    }

    // MARK: - CCPA opt-out

    /// Persist the user's explicit CCPA/CPRA "Do Not Sell or Share" choice (TRUST-2591). A value not
    /// chosen by the setter (an adopt, the neutral reset) has no known decision time, so any earlier
    /// setter time is removed with it rather than left paired with this value (TRUST-2902).
    public func saveCcpaOptout(_ optedOut: Bool) {
        userDefaults.set(optedOut, forKey: Keys.ccpaOptout)
        userDefaults.removeObject(forKey: Keys.ccpaDecisionTs)
    }

    /// Persist the host app's CCPA choice and when it was made (TRUST-2902), together. The time is
    /// monotonic, as ``saveDecisionTs(_:now:)`` is: two toggles in the same second must not tie,
    /// since the edge keeps an opt-out on a tie.
    func saveCcpaChoice(_ optedOut: Bool, now: Int64 = ConsentStorage.nowSeconds()) {
        let value: Int64
        if let previous = loadCcpaDecisionTs(now: now) {
            value = min(max(now, previous + 1), now + Self.decisionTsStoredToleranceSeconds)
        } else {
            value = now
        }
        userDefaults.set(optedOut, forKey: Keys.ccpaOptout)
        userDefaults.set(String(value), forKey: Keys.ccpaDecisionTs)
    }

    /// Load the user's explicit CCPA/CPRA "Do Not Sell or Share" choice; `false` when never set.
    public func loadCcpaOptout() -> Bool {
        userDefaults.bool(forKey: Keys.ccpaOptout)
    }

    /// Mark (or clear) that a CCPA choice made while bound has not reached the Universal Consent
    /// record yet: the setter had no category choice or session to write with, or its write failed.
    /// While set, a found record's `ccpa_optout` must not replace the local flag on a re-sync or
    /// rehydrate, or the device would silently lose its own unsent choice.
    func saveCcpaWritePending(_ pending: Bool) {
        if pending {
            userDefaults.set(true, forKey: Keys.ccpaWritePending)
        } else {
            userDefaults.removeObject(forKey: Keys.ccpaWritePending)
        }
    }

    /// Whether a bound CCPA choice is still waiting to reach the record; `false` when none is stored.
    func loadCcpaWritePending() -> Bool {
        userDefaults.bool(forKey: Keys.ccpaWritePending)
    }

    /// Put back a CCPA flag and the setter time it had (`nil` removes it), as one pair: a re-sync that
    /// writes the user's own flag after the rehydrate adopted the record's restores both.
    func restoreCcpaChoice(_ choice: (optedOut: Bool, decisionTs: Int64?)) {
        userDefaults.set(choice.optedOut, forKey: Keys.ccpaOptout)
        if let decisionTs = choice.decisionTs {
            userDefaults.set(String(decisionTs), forKey: Keys.ccpaDecisionTs)
        } else {
            userDefaults.removeObject(forKey: Keys.ccpaDecisionTs)
        }
    }

    /// When the stored CCPA choice was made: by the setter (``saveCcpaChoice(_:now:)``), or, for a
    /// flag adopted from a record, that record's `updated_at` (``restoreCcpaChoice(_:)``), which is
    /// the floor the next setter time is stamped after. `nil` when unknown. A CCPA-only write sends it as `decision_ts`, so a choice that waited for a session
    /// (pending) is ranked by when the user made it, not by when it was finally sent: a late flush
    /// cannot out-rank a newer choice made on another device in between. Its own key: the category
    /// choice's time never stamps the CCPA flag. Unknown (never set by the
    /// setter, set before this was recorded, or bogusly far ahead of this clock, as for
    /// ``loadDecisionTs(now:)``). `nil` sends no provenance: the edge stamps the request time.
    func loadCcpaDecisionTs(now: Int64 = ConsentStorage.nowSeconds()) -> Int64? {
        guard let raw = userDefaults.string(forKey: Keys.ccpaDecisionTs),
              let value = Int64(raw), value >= 0
        else { return nil }
        return value <= now + Self.decisionTsStoredToleranceSeconds ? value : nil
    }

    // MARK: - Unique ID

    /// Get or create a unique identifier for this user
    /// - Returns: The unique identifier (UUID string)
    public func getOrCreateUniqueId() -> String {
        if let existingId = userDefaults.string(forKey: Keys.uniqueId) {
            return existingId
        }
        let newId = UUID().uuidString
        userDefaults.set(newId, forKey: Keys.uniqueId)
        return newId
    }

    // MARK: - Configuration Version

    /// Save the configuration version
    /// - Parameter version: The version string to save
    public func saveConfigVersion(_ version: String) {
        userDefaults.set(version, forKey: Keys.version)
    }

    /// Load the stored configuration version
    /// - Returns: The version string, or nil if none stored
    public func loadConfigVersion() -> String? {
        userDefaults.string(forKey: Keys.version)
    }

    // MARK: - Locale

    /// Save the current locale code
    /// - Parameter localeCode: The locale code (e.g., "en", "es")
    public func saveLocaleCode(_ localeCode: String) {
        userDefaults.set(localeCode, forKey: Keys.localeCode)
    }

    /// Load the stored locale code
    /// - Returns: The locale code, or nil if none stored
    public func loadLocaleCode() -> String? {
        userDefaults.string(forKey: Keys.localeCode)
    }

    // MARK: - Config Cache

    /// Save configuration to cache
    /// - Parameter config: The configuration to cache
    /// - Throws: ConsentError.storageError if encoding fails
    public func saveConfigCache(_ config: ConsentConfig) throws {
        do {
            let data = try encoder.encode(config)
            userDefaults.set(data, forKey: Keys.configCache)
        } catch {
            throw ConsentError.storageError("Failed to encode config: \(error.localizedDescription)")
        }
    }

    /// Load cached configuration
    /// - Returns: The cached config, or nil if none exists
    public func loadConfigCache() -> ConsentConfig? {
        guard let data = userDefaults.data(forKey: Keys.configCache) else {
            return nil
        }
        return try? decoder.decode(ConsentConfig.self, from: data)
    }

    // MARK: - Pending Events

    /// Save pending events queue
    /// - Parameter events: Array of event data to save
    /// - Throws: ConsentError.storageError if encoding fails
    public func savePendingEvents(_ events: [[String: Any]]) throws {
        do {
            let data = try JSONSerialization.data(withJSONObject: events)
            userDefaults.set(data, forKey: Keys.pendingEvents)
        } catch {
            throw ConsentError.storageError("Failed to encode events: \(error.localizedDescription)")
        }
    }

    /// Load pending events queue
    /// - Returns: Array of pending events, or empty array if none
    public func loadPendingEvents() -> [[String: Any]] {
        guard let data = userDefaults.data(forKey: Keys.pendingEvents),
              let events = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return []
        }
        return events
    }

    // MARK: - Clear

    /// Clear all stored consent data
    public func clearAll() {
        let keys = [
            Keys.preferences,
            Keys.uniqueId,
            Keys.version,
            Keys.localeCode,
            Keys.configCache,
            Keys.pendingEvents,
            Keys.boundUserHash,
            Keys.ccpaOptout,
            Keys.ccpaWritePending,
            Keys.syncState,
            Keys.decisionTs,
            Keys.ccpaDecisionTs,
        ]
        keys.forEach { userDefaults.removeObject(forKey: $0) }
    }
}

/// What the last successful Universal Consent sync left on this device (TRUST-2902), persisted next
/// to the bound user hash so it survives an app relaunch.
struct UniversalConsentSyncState: Codable, Equatable {
    /// The bound identity this state belongs to. It is ignored for any other identity.
    let userHash: String
    /// The stored local choice right after the sync. After an adopt this is the RECONCILED view
    /// (ATT, GPC or the record's ccpa_optout can force categories off), so it must never be written
    /// back as though the user chose it. `nil` when nothing was stored.
    let syncedLocal: ConsentPreferences?
    /// The RAW choice the record held after the sync: what it wrote, or the record it adopted.
    /// `nil` on a miss with nothing written, or a signal-only record.
    let syncedRaw: ConsentPreferences?
}
