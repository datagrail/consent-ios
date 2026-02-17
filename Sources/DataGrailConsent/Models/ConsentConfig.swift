import Foundation

/// Root configuration object for the consent banner
public struct ConsentConfig: Codable {
    public let version: String
    public let consentContainerVersionId: String
    public let dgCustomerId: String
    public let publishDate: Int64
    public let dch: String
    public let dc: String
    public let privacyDomain: String
    public let plugins: Plugins
    public let testMode: Bool
    public let ignoreDoNotTrack: Bool
    public let trackingDetailsUrl: String
    public let consentMode: String
    public let showBanner: Bool
    public let consentPolicy: ConsentPolicy
    public let gppUsNat: Bool
    public let initialCategories: InitialCategories
    public let layout: Layout

    enum CodingKeys: String, CodingKey {
        case version, consentContainerVersionId, dgCustomerId, dch, dc, privacyDomain
        case plugins, testMode, ignoreDoNotTrack, trackingDetailsUrl, consentMode
        case showBanner, consentPolicy, gppUsNat, initialCategories, layout
        case publishDate = "p"
    }
}

/// Plugin configuration flags
public struct Plugins: Codable {
    public let scriptControl: Bool
    public let allCookieSubdomains: Bool
    public let cookieBlocking: Bool
    public let localStorageBlocking: Bool
    public let syncOTConsent: Bool
}

/// Consent policy information
public struct ConsentPolicy: Codable {
    public let name: String
    public let `default`: Bool
}

/// Initial category settings for different scenarios
public struct InitialCategories: Codable {
    public let respectGpc: Bool
    public let respectDnt: Bool
    public let respectOptout: Bool
    public let initial: [String]
    public let gpc: [String]
    public let optout: [String]

    enum CodingKeys: String, CodingKey {
        case respectGpc = "respect_gpc"
        case respectDnt = "respect_dnt"
        case respectOptout = "respect_optout"
        case initial, gpc, optout
    }
}

/// Layout configuration for the consent banner
public struct Layout: Codable {
    public let id: String
    public let name: String
    public let description: String?
    public let status: String
    public let defaultLayout: Bool
    public let collapsedOnMobile: Bool
    public let firstLayerId: String
    public let gpcDntLayerId: String?
    public let consentLayers: [String: ConsentLayer]

    enum CodingKeys: String, CodingKey {
        case id, name, description, status
        case defaultLayout = "default_layout"
        case collapsedOnMobile = "collapsed_on_mobile"
        case firstLayerId = "first_layer_id"
        case gpcDntLayerId = "gpc_dnt_layer_id"
        case consentLayers = "consent_layers"
    }
}

/// A single consent layer (screen) in the banner flow
public struct ConsentLayer: Codable {
    public let id: String
    public let name: String
    public let theme: String
    public let position: String
    public let showCloseButton: Bool
    public let bannerApiId: String
    public let elements: [ConsentLayerElement]

    enum CodingKeys: String, CodingKey {
        case id, name, theme, position, elements
        case showCloseButton = "show_close_button"
        case bannerApiId = "banner_api_id"
    }
}

/// A UI element within a consent layer
public struct ConsentLayerElement: Codable {
    public let id: String
    public let order: Int
    public let type: String

    // Text element fields
    public let style: String?

    // Button element fields
    public let buttonAction: String?
    public let targetConsentLayer: String?
    public let categories: [String]?

    // Link element fields
    public let links: [LinkItem]?

    // Category element fields
    public let consentLayerCategories: [ConsentLayerCategory]?
    public let showTrackingDetailsLink: Bool?
    public let consentLayerCategoriesConfigId: String?
    // Note: trackingDetailsLinkTranslations can be either an array or dictionary in different configs
    public let trackingDetailsLinkTranslations: [String: TrackingDetailsLinkTranslation]?

    // Browser signal notice fields
    public let showIcon: Bool?
    public let consentLayerBrowserSignalNoticeConfigId: String?
    public let browserSignalNoticeTranslations: [String: BrowserSignalNoticeTranslation]?

    // Tracking details element fields
    public let showTrackingServices: Bool?
    public let showCookies: Bool?
    public let showIcons: Bool?
    public let groupByVendor: Bool?

    // Common
    public let translations: [String: ElementTranslation]?

    enum CodingKeys: String, CodingKey {
        case id, order, type, style, links, translations, categories
        case buttonAction = "button_action"
        case targetConsentLayer = "target_consent_layer"
        case consentLayerCategories = "consent_layer_categories"
        case showTrackingDetailsLink = "show_tracking_details_link"
        case consentLayerCategoriesConfigId = "consent_layer_categories_config_id"
        case trackingDetailsLinkTranslations = "tracking_details_link_translations"
        case showIcon = "show_icon"
        case consentLayerBrowserSignalNoticeConfigId = "consent_layer_browser_signal_notice_config_id"
        case browserSignalNoticeTranslations = "browser_signal_notice_translations"
        case showTrackingServices = "show_tracking_services"
        case showCookies = "show_cookies"
        case showIcons = "show_icons"
        case groupByVendor = "group_by_vendor"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        order = try container.decode(Int.self, forKey: .order)
        type = try container.decode(String.self, forKey: .type)
        style = try container.decodeIfPresent(String.self, forKey: .style)
        buttonAction = try container.decodeIfPresent(String.self, forKey: .buttonAction)
        targetConsentLayer = try container.decodeIfPresent(String.self, forKey: .targetConsentLayer)
        categories = try container.decodeIfPresent([String].self, forKey: .categories)
        links = try container.decodeIfPresent([LinkItem].self, forKey: .links)
        consentLayerCategories = try container.decodeIfPresent(
            [ConsentLayerCategory].self, forKey: .consentLayerCategories
        )
        showTrackingDetailsLink = try container.decodeIfPresent(
            Bool.self, forKey: .showTrackingDetailsLink
        )
        consentLayerCategoriesConfigId = try container.decodeIfPresent(
            String.self, forKey: .consentLayerCategoriesConfigId
        )
        showIcon = try container.decodeIfPresent(Bool.self, forKey: .showIcon)
        consentLayerBrowserSignalNoticeConfigId = try container.decodeIfPresent(
            String.self, forKey: .consentLayerBrowserSignalNoticeConfigId
        )
        browserSignalNoticeTranslations = try container.decodeIfPresent(
            [String: BrowserSignalNoticeTranslation].self, forKey: .browserSignalNoticeTranslations
        )
        showTrackingServices = try container.decodeIfPresent(Bool.self, forKey: .showTrackingServices)
        showCookies = try container.decodeIfPresent(Bool.self, forKey: .showCookies)
        showIcons = try container.decodeIfPresent(Bool.self, forKey: .showIcons)
        groupByVendor = try container.decodeIfPresent(Bool.self, forKey: .groupByVendor)
        translations = try container.decodeIfPresent([String: ElementTranslation].self, forKey: .translations)

        // Handle trackingDetailsLinkTranslations which can be either array or dictionary
        if let dictValue = try? container.decodeIfPresent(
            [String: TrackingDetailsLinkTranslation].self, forKey: .trackingDetailsLinkTranslations
        ) {
            trackingDetailsLinkTranslations = dictValue
        } else if let arrayValue = try? container.decodeIfPresent(
            [TrackingDetailsLinkTranslation].self, forKey: .trackingDetailsLinkTranslations
        ) {
            // Convert array to dictionary using locale as key
            var dict: [String: TrackingDetailsLinkTranslation] = [:]
            for item in arrayValue {
                if let locale = item.locale {
                    dict[locale] = item
                }
            }
            trackingDetailsLinkTranslations = dict.isEmpty ? nil : dict
        } else {
            trackingDetailsLinkTranslations = nil
        }
    }

    // Explicit initializer for test usage
    public init(
        id: String,
        order: Int,
        type: String,
        style: String?,
        buttonAction: String?,
        targetConsentLayer: String?,
        categories: [String]?,
        links: [LinkItem]?,
        consentLayerCategories: [ConsentLayerCategory]?,
        showTrackingDetailsLink: Bool?,
        consentLayerCategoriesConfigId: String?,
        trackingDetailsLinkTranslations: [String: TrackingDetailsLinkTranslation]?,
        showIcon: Bool?,
        consentLayerBrowserSignalNoticeConfigId: String?,
        browserSignalNoticeTranslations: [String: BrowserSignalNoticeTranslation]?,
        showTrackingServices: Bool?,
        showCookies: Bool?,
        showIcons: Bool?,
        groupByVendor: Bool?,
        translations: [String: ElementTranslation]?
    ) {
        self.id = id
        self.order = order
        self.type = type
        self.style = style
        self.buttonAction = buttonAction
        self.targetConsentLayer = targetConsentLayer
        self.categories = categories
        self.links = links
        self.consentLayerCategories = consentLayerCategories
        self.showTrackingDetailsLink = showTrackingDetailsLink
        self.consentLayerCategoriesConfigId = consentLayerCategoriesConfigId
        self.trackingDetailsLinkTranslations = trackingDetailsLinkTranslations
        self.showIcon = showIcon
        self.consentLayerBrowserSignalNoticeConfigId = consentLayerBrowserSignalNoticeConfigId
        self.browserSignalNoticeTranslations = browserSignalNoticeTranslations
        self.showTrackingServices = showTrackingServices
        self.showCookies = showCookies
        self.showIcons = showIcons
        self.groupByVendor = groupByVendor
        self.translations = translations
    }
}

/// Translation for an element
public struct ElementTranslation: Codable {
    public let id: String?
    public let locale: String?
    public let value: String?
    public let text: String?
    public let url: String?
}

/// A link item within a link element
public struct LinkItem: Codable {
    public let id: String
    public let order: Int
    public let translations: [String: ElementTranslation]
}

/// Tracking details link translation
public struct TrackingDetailsLinkTranslation: Codable {
    public let id: String?
    public let locale: String?
    public let value: String?
}

/// Browser signal notice translation
public struct BrowserSignalNoticeTranslation: Codable {
    public let id: String?
    public let locale: String?
    public let value: String?
}

/// A consent category within a category element
public struct ConsentLayerCategory: Codable {
    public let id: String
    public let consentCategoryId: String
    public let order: Int
    public let hidden: Bool
    public let primitive: String
    public let alwaysOn: Bool
    public let gtmKey: String
    public let uuids: [String]
    public let cookiePatterns: [String]
    public let translations: [String: CategoryTranslation]
    public let showTrackingDetailsLink: Bool

    enum CodingKeys: String, CodingKey {
        case id, order, hidden, primitive, uuids, translations
        case consentCategoryId = "consent_category_id"
        case alwaysOn = "always_on"
        case gtmKey = "gtm_key"
        case cookiePatterns = "cookie_patterns"
        case showTrackingDetailsLink = "show_tracking_details_link"
    }
}

/// Translation for a category
public struct CategoryTranslation: Codable {
    public let id: String?
    public let locale: String?
    public let name: String?
    public let description: String?
    public let essentialLabel: String?
    public let trackingDetailsLink: String?

    enum CodingKeys: String, CodingKey {
        case id, locale, name, description
        case essentialLabel = "essential_label"
        case trackingDetailsLink = "tracking_details_link"
    }
}
