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
    /// pending queue) intact — unlike ``clearAll()``.
    public func removePreferences() {
        userDefaults.removeObject(forKey: Keys.preferences)
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

    /// Persist the user's explicit CCPA/CPRA "Do Not Sell or Share" choice (TRUST-2591).
    public func saveCcpaOptout(_ optedOut: Bool) {
        userDefaults.set(optedOut, forKey: Keys.ccpaOptout)
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
