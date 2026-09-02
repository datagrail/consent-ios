import Foundation

/// Consent preferences in the Universal Consent wire format.
///
/// Unlike ``ConsentPreferences`` (an ARRAY of ``CategoryConsent``), the Universal Consent
/// wire format carries `cookieOptions` as a MAP of `{ categoryKey: Bool }`. Both the read
/// and write paths use the map shape, matching the web and Android SDKs.
public struct UniversalConsentPreferences: Codable, Equatable {
    public let isCustomised: Bool
    public let cookieOptions: [String: Bool]

    public init(isCustomised: Bool = false, cookieOptions: [String: Bool] = [:]) {
        self.isCustomised = isCustomised
        self.cookieOptions = cookieOptions
    }

    // Swift synthesizes a decoder that FAILS on a missing key rather than falling back to
    // the property default, so the defaults above would never apply to a real response.
    // An unbannered user's record legitimately carries no `cookieOptions` at all, and a
    // `not_found` response carries neither key — both must decode, not throw.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isCustomised = try container.decodeIfPresent(Bool.self, forKey: .isCustomised) ?? false
        cookieOptions = try container.decodeIfPresent([String: Bool].self, forKey: .cookieOptions) ?? [:]
    }
}

/// A Universal Consent record as returned by `GET /universal_consent`.
///
/// IMPORTANT: this data is RAW and UNRECONCILED. The server never computes an "effective"
/// consent state — it returns the stored ``consentPreferences`` plus the signals it knows
/// about (``gpc``, ``tcfString``, ``gppString``) exactly as written. Clients MUST reconcile
/// locally before acting on it; see ``ConsentService/reconcile(cookieOptions:suppress:essentialCategoryKeys:)``.
public struct UniversalConsentRecord: Codable, Equatable {
    /// `"found"` or `"not_found"`.
    public let status: String
    // `var` so `withCookieOptions` can copy-mutate `self` rather than re-list every field
    // through the initializer — a future field then carries over automatically instead of
    // silently resetting to its default.
    public var consentPreferences: UniversalConsentPreferences?
    public let consentMode: String?
    public let ccpaOptout: Bool
    public let platform: String?
    public let policyName: String?
    public let configVersion: String?
    public let updatedAt: String?

    /// Stored GPC, recorded on the web where GPC exists. There is no GPC on iOS — this is
    /// a signal the record carries, not one this device can produce.
    public let gpc: Bool
    public let tcfString: String?
    public let gppString: String?

    public var isFound: Bool { status == "found" }

    enum CodingKeys: String, CodingKey {
        case status, platform, gpc
        case consentPreferences = "consent_preferences"
        case consentMode = "consent_mode"
        case ccpaOptout = "ccpa_optout"
        case policyName = "policy_name"
        case configVersion = "config_version"
        case updatedAt = "updated_at"
        case tcfString = "tcf_string"
        case gppString = "gpp_string"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        consentPreferences = try container.decodeIfPresent(
            UniversalConsentPreferences.self, forKey: .consentPreferences
        )
        consentMode = try container.decodeIfPresent(String.self, forKey: .consentMode)
        ccpaOptout = try container.decodeIfPresent(Bool.self, forKey: .ccpaOptout) ?? false
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        policyName = try container.decodeIfPresent(String.self, forKey: .policyName)
        configVersion = try container.decodeIfPresent(String.self, forKey: .configVersion)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        gpc = try container.decodeIfPresent(Bool.self, forKey: .gpc) ?? false
        tcfString = try container.decodeIfPresent(String.self, forKey: .tcfString)
        gppString = try container.decodeIfPresent(String.self, forKey: .gppString)
    }

    public init(
        status: String,
        consentPreferences: UniversalConsentPreferences? = nil,
        consentMode: String? = nil,
        ccpaOptout: Bool = false,
        platform: String? = nil,
        policyName: String? = nil,
        configVersion: String? = nil,
        updatedAt: String? = nil,
        gpc: Bool = false,
        tcfString: String? = nil,
        gppString: String? = nil
    ) {
        self.status = status
        self.consentPreferences = consentPreferences
        self.consentMode = consentMode
        self.ccpaOptout = ccpaOptout
        self.platform = platform
        self.policyName = policyName
        self.configVersion = configVersion
        self.updatedAt = updatedAt
        self.gpc = gpc
        self.tcfString = tcfString
        self.gppString = gppString
    }

    /// A copy of this record carrying a different `cookieOptions` map, used to return the
    /// reconciled state without mutating the raw decoded record.
    func withCookieOptions(_ cookieOptions: [String: Bool]) -> UniversalConsentRecord {
        // Copy self and swap only the preferences, so every other field — including any added
        // in the future — carries over untouched rather than defaulting through the initializer.
        var copy = self
        copy.consentPreferences = UniversalConsentPreferences(
            isCustomised: consentPreferences?.isCustomised ?? false,
            cookieOptions: cookieOptions
        )
        return copy
    }
}
