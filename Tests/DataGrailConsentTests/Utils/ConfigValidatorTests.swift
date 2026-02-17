@testable import DataGrailConsent
import XCTest

final class ConfigValidatorTests: XCTestCase {
    func testValidConfigPasses() throws {
        let config = createValidConfig()

        // Should not throw
        XCTAssertNoThrow(try ConfigValidator.validate(config))
    }

    func testMissingVersionFails() {
        var config = createValidConfig()
        config = ConsentConfig(
            version: "",
            consentContainerVersionId: config.consentContainerVersionId,
            dgCustomerId: config.dgCustomerId,
            publishDate: config.publishDate,
            dch: config.dch,
            dc: config.dc,
            privacyDomain: config.privacyDomain,
            plugins: config.plugins,
            testMode: config.testMode,
            ignoreDoNotTrack: config.ignoreDoNotTrack,
            trackingDetailsUrl: config.trackingDetailsUrl,
            consentMode: config.consentMode,
            showBanner: config.showBanner,
            consentPolicy: config.consentPolicy,
            gppUsNat: config.gppUsNat,
            initialCategories: config.initialCategories,
            layout: config.layout
        )

        XCTAssertThrowsError(try ConfigValidator.validate(config)) { error in
            guard case let ConsentError.validationError(message) = error else {
                XCTFail("Expected validationError")
                return
            }
            XCTAssertTrue(message.contains("version"))
        }
    }

    func testInvalidConsentModeFails() {
        var config = createValidConfig()
        config = ConsentConfig(
            version: config.version,
            consentContainerVersionId: config.consentContainerVersionId,
            dgCustomerId: config.dgCustomerId,
            publishDate: config.publishDate,
            dch: config.dch,
            dc: config.dc,
            privacyDomain: config.privacyDomain,
            plugins: config.plugins,
            testMode: config.testMode,
            ignoreDoNotTrack: config.ignoreDoNotTrack,
            trackingDetailsUrl: config.trackingDetailsUrl,
            consentMode: "invalid",
            showBanner: config.showBanner,
            consentPolicy: config.consentPolicy,
            gppUsNat: config.gppUsNat,
            initialCategories: config.initialCategories,
            layout: config.layout
        )

        XCTAssertThrowsError(try ConfigValidator.validate(config)) { error in
            guard case let ConsentError.validationError(message) = error else {
                XCTFail("Expected validationError")
                return
            }
            XCTAssertTrue(message.contains("consentMode"))
        }
    }

    // MARK: - Helper Methods

    // swiftlint:disable:next function_body_length
    private func createValidConfig() -> ConsentConfig {
        let element = ConsentLayerElement(
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
            translations: [
                "en": ElementTranslation(id: "t1", locale: "en", value: "Test", text: nil, url: nil),
            ]
        )

        let layer = ConsentLayer(
            id: "layer1",
            name: "First Layer",
            theme: "neutral",
            position: "bottom",
            showCloseButton: true,
            bannerApiId: "first",
            elements: [element]
        )

        let layout = Layout(
            id: "layout1",
            name: "Test Layout",
            description: nil,
            status: "published",
            defaultLayout: true,
            collapsedOnMobile: false,
            firstLayerId: "layer1",
            gpcDntLayerId: nil,
            consentLayers: ["layer1": layer]
        )

        return ConsentConfig(
            version: "1.0.0",
            consentContainerVersionId: "container1",
            dgCustomerId: "customer1",
            publishDate: 0,
            dch: "categorize",
            dc: "dg-category-essential",
            privacyDomain: "consent.datagrail.io",
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
            consentPolicy: ConsentPolicy(name: "GDPR", default: true),
            gppUsNat: false,
            initialCategories: InitialCategories(
                respectGpc: false,
                respectDnt: false,
                respectOptout: false,
                initial: ["dg-category-essential"],
                gpc: [],
                optout: []
            ),
            layout: layout
        )
    }
}
