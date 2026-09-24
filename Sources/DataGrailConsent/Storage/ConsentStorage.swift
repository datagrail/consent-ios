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

    /// Clear the Universal Consent identity binding.
    public func clearBoundUserHash() {
        userDefaults.removeObject(forKey: Keys.boundUserHash)
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
        ]
        keys.forEach { userDefaults.removeObject(forKey: $0) }
    }
}
