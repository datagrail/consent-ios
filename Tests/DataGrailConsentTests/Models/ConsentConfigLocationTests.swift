import XCTest

@testable import DataGrailConsent

final class ConsentConfigLocationTests: XCTestCase {
    func testParseGdprFranceConfig() throws {
        guard let configUrl = Bundle.module.url(forResource: "config-gdpr-fr", withExtension: "json")
        else {
            XCTFail("Could not find config-gdpr-fr.json in test bundle")
            return
        }

        let configData = try Data(contentsOf: configUrl)
        let config = try JSONDecoder().decode(ConsentConfig.self, from: configData)

        // Verify top-level properties
        XCTAssertEqual(config.version, "f697b4ac-341a-4e5a-9794-d09e23148771")
        XCTAssertEqual(config.dgCustomerId, "c30be0d2-795f-40af-9f70-502b83f7bb68")
        XCTAssertEqual(config.publishDate, 1_774_471_086_457)
        XCTAssertEqual(config.dch, "allow_all")
        XCTAssertEqual(config.dc, "dg-category-marketing")
        XCTAssertEqual(config.privacyDomain, "bradleyy.dg-dev.com")
        XCTAssertFalse(config.testMode)
        XCTAssertEqual(config.consentMode, "optin")
        XCTAssertTrue(config.showBanner)
        XCTAssertFalse(config.gppUsNat)

        // Verify plugins
        XCTAssertTrue(config.plugins.scriptControl)
        XCTAssertTrue(config.plugins.cookieBlocking)
        XCTAssertTrue(config.plugins.syncOTConsent)

        // Verify consent policy — GDPR for France
        XCTAssertEqual(config.consentPolicy.name, "GDPR")
        XCTAssertFalse(config.consentPolicy.default)

        // Verify initial categories — optin mode means only essential initially
        XCTAssertTrue(config.initialCategories.respectGpc)
        XCTAssertTrue(config.initialCategories.respectDnt)
        XCTAssertTrue(config.initialCategories.respectOptout)
        XCTAssertEqual(config.initialCategories.initial.count, 1)
        XCTAssertEqual(config.initialCategories.initial.first, "dg-category-essential")
        XCTAssertEqual(config.initialCategories.gpc.count, 1)
        XCTAssertEqual(config.initialCategories.optout.count, 1)

        // Verify layout
        XCTAssertEqual(config.layout.name, "Global Layout")
        XCTAssertTrue(config.layout.defaultLayout)
        XCTAssertFalse(config.layout.collapsedOnMobile)
        XCTAssertNil(config.layout.gpcDntLayerId)
        XCTAssertEqual(config.layout.consentLayers.count, 2)

        // Verify categories layer has 4 consent categories
        let categoriesLayer = config.layout.consentLayers["33e8abaf-f967-44d8-8ad4-56c9f18028f6"]
        let categoryElement = categoriesLayer?.elements.first { $0.type == "ConsentLayerCategoryElement" }
        XCTAssertEqual(categoryElement?.consentLayerCategories?.count, 4)

        // Verify language picker elements are parsed
        let defaultLayer = config.layout.consentLayers["1b4c5952-ab0b-4f6d-82f4-c28a430e9d59"]
        let languagePickers = defaultLayer?.elements.filter {
            $0.type == "ConsentLayerLanguagePickerElement"
        }
        XCTAssertEqual(languagePickers?.count, 1)
    }

    func testParseCpraUsCaliforniaConfig() throws {
        guard let configUrl = Bundle.module.url(forResource: "config-cpra-us-ca", withExtension: "json")
        else {
            XCTFail("Could not find config-cpra-us-ca.json in test bundle")
            return
        }

        let configData = try Data(contentsOf: configUrl)
        let config = try JSONDecoder().decode(ConsentConfig.self, from: configData)

        // Verify top-level properties
        XCTAssertEqual(config.version, "f697b4ac-341a-4e5a-9794-d09e23148771")
        XCTAssertEqual(config.dgCustomerId, "c30be0d2-795f-40af-9f70-502b83f7bb68")
        XCTAssertEqual(config.publishDate, 1_774_471_086_415)
        XCTAssertEqual(config.dch, "allow_all")
        XCTAssertEqual(config.dc, "dg-category-marketing")
        XCTAssertEqual(config.privacyDomain, "bradleyy.dg-dev.com")
        XCTAssertFalse(config.testMode)
        XCTAssertEqual(config.consentMode, "optout")
        XCTAssertTrue(config.showBanner)
        XCTAssertFalse(config.gppUsNat)

        // Verify plugins
        XCTAssertTrue(config.plugins.scriptControl)
        XCTAssertTrue(config.plugins.cookieBlocking)
        XCTAssertTrue(config.plugins.syncOTConsent)

        // Verify consent policy
        XCTAssertEqual(config.consentPolicy.name, "CPRA")
        XCTAssertFalse(config.consentPolicy.default)

        // Verify initial categories — optout mode has all categories initially
        XCTAssertTrue(config.initialCategories.respectGpc)
        XCTAssertTrue(config.initialCategories.respectOptout)
        XCTAssertEqual(config.initialCategories.initial.count, 4)
        XCTAssertTrue(config.initialCategories.initial.contains("dg-category-essential"))
        XCTAssertTrue(config.initialCategories.initial.contains("dg-category-marketing"))
        XCTAssertEqual(config.initialCategories.optout.count, 3)

        // Verify layout
        XCTAssertEqual(config.layout.name, "Global Layout")
        XCTAssertTrue(config.layout.defaultLayout)
        XCTAssertNil(config.layout.gpcDntLayerId)
        XCTAssertEqual(config.layout.consentLayers.count, 2)

        // Verify categories layer
        let categoriesLayer = config.layout.consentLayers["33e8abaf-f967-44d8-8ad4-56c9f18028f6"]
        let categoryElement = categoriesLayer?.elements.first { $0.type == "ConsentLayerCategoryElement" }
        XCTAssertEqual(categoryElement?.consentLayerCategories?.count, 4)
        let essential = categoryElement?.consentLayerCategories?.first {
            $0.gtmKey == "dg-category-essential"
        }
        XCTAssertTrue(essential?.alwaysOn == true)

        // Verify language picker and open_tcf button
        let defaultLayer = config.layout.consentLayers["1b4c5952-ab0b-4f6d-82f4-c28a430e9d59"]
        let pickers = defaultLayer?.elements.filter { $0.type == "ConsentLayerLanguagePickerElement" }
        XCTAssertEqual(pickers?.count, 1)
        let tcfButton = defaultLayer?.elements.first { $0.buttonAction == "open_tcf" }
        XCTAssertNotNil(tcfButton)
        XCTAssertEqual(tcfButton?.translations?["en"]?.value, "Vendor Preferences")
    }
}
