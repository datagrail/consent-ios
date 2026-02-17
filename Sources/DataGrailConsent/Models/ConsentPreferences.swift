import Foundation

/// Represents user's consent preferences
public struct ConsentPreferences: Codable, Equatable {
    /// Whether the user has customized their preferences (vs using defaults)
    public var isCustomised: Bool

    /// Array of consent options for each category
    public var cookieOptions: [CategoryConsent]

    public init(isCustomised: Bool, cookieOptions: [CategoryConsent]) {
        self.isCustomised = isCustomised
        self.cookieOptions = cookieOptions
    }

    /// Check if a specific category is enabled
    /// - Parameter categoryKey: The GTM key of the category (e.g., "category_marketing")
    /// - Returns: True if the category is enabled, false otherwise
    public func isCategoryEnabled(_ categoryKey: String) -> Bool {
        cookieOptions.first(where: { $0.gtmKey == categoryKey })?.isEnabled ?? false
    }
}

/// Represents consent status for a single category
public struct CategoryConsent: Codable, Equatable {
    /// The GTM key identifying this category
    public let gtmKey: String

    /// Whether this category is enabled/consented to
    public var isEnabled: Bool

    public init(gtmKey: String, isEnabled: Bool) {
        self.gtmKey = gtmKey
        self.isEnabled = isEnabled
    }

    enum CodingKeys: String, CodingKey {
        case gtmKey = "gtm_key"
        case isEnabled
    }
}
