@testable import DataGrailConsent

/// Shared config fixture for the Universal Consent suites. Lives outside the test classes so
/// they can each stay under SwiftLint's `type_body_length` limit, and so the three suites
/// cannot drift onto subtly different configs.
enum UCFixtures {
    static let customerId = "ac46d8ad-a67a-431f-a5d5-9e3eb922dae7"
    static let projectId = "proj_abc123"

    /// Minimal layer so the config passes `ConfigValidator` when loaded through `ConfigService`.
    private static let firstLayer = ConsentLayer(
        id: "layer1",
        name: "First Layer",
        position: "bottom",
        showCloseButton: true,
        bannerApiId: "first",
        elements: [
            ConsentLayerElement(
                id: "elem1",
                order: 1,
                type: "ConsentLayerTextElement",
                style: nil,
                buttonAction: nil,
                targetConsentLayer: nil,
                categories: nil,
                links: nil,
                consentLayerCategories: nil,
                showTrackingDetailsLink: nil,
                consentLayerCategoriesConfigId: nil,
                trackingDetailsLinkTranslations: nil,
                showIcon: nil,
                consentLayerBrowserSignalNoticeConfigId: nil,
                browserSignalNoticeTranslations: nil,
                showTrackingServices: nil,
                showCookies: nil,
                showIcons: nil,
                groupByVendor: nil,
                translations: ["en": ElementTranslation(id: "t1", locale: "en", value: "Test", text: nil, url: nil)]
            ),
        ]
    )

    static func makeConfig(privacyDomain: String, consentProjectId: String? = projectId) -> ConsentConfig {
        ConsentConfig(
            version: "1.0.0",
            consentContainerVersionId: "container1",
            dgCustomerId: customerId,
            publishDate: 0,
            dch: "categorize",
            dc: "dg-category-essential",
            privacyDomain: privacyDomain,
            plugins: Plugins(
                scriptControl: false,
                allCookieSubdomains: false,
                cookieBlocking: false,
                localStorageBlocking: false,
                syncOTConsent: false
            ),
            testMode: false,
            ignoreDoNotTrack: false,
            trackingDetailsUrl: "https://example.com/tracking",
            consentMode: "optin",
            showBanner: true,
            consentPolicy: ConsentPolicy(name: "GDPR", uuid: nil, default: true),
            gppUsNat: false,
            initialCategories: InitialCategories(
                respectGpc: true,
                respectDnt: false,
                respectOptout: false,
                initial: ["dg-category-essential"],
                gpc: [],
                optout: []
            ),
            layout: Layout(
                id: "layout1",
                name: "Test Layout",
                description: nil,
                status: "published",
                defaultLayout: true,
                collapsedOnMobile: false,
                firstLayerId: "layer1",
                gpcDntLayerId: nil,
                consentLayers: ["layer1": firstLayer]
            ),
            consentProjectId: consentProjectId,
            universalConsent: UniversalConsentConfig(enabled: true, syncOptout: false)
        )
    }
}
