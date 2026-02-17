import XCTest

@testable import DataGrailConsent

final class ConsentConfigParserTests: XCTestCase {
    func testParseRealConfigFile() throws {
        // Load the real config.json from test resources
        guard let configUrl = Bundle.module.url(forResource: "test-config", withExtension: "json")
        else {
            XCTFail("Could not find test-config.json in test bundle")
            return
        }

        let configData = try Data(contentsOf: configUrl)

        // Parse the config
        let decoder = JSONDecoder()
        let config = try decoder.decode(ConsentConfig.self, from: configData)

        // Verify top-level properties
        XCTAssertEqual(config.version, "cc959465-747d-4c81-8bc1-5dcd34dc3756")
        XCTAssertEqual(config.consentContainerVersionId, "0dd5bdf3-b55e-4d97-8a06-e14b17660b94")
        XCTAssertEqual(config.dgCustomerId, "ac46d8ad-a67a-431f-a5d5-9e3eb922dae7")
        XCTAssertEqual(config.publishDate, 1_765_415_800_250)
        XCTAssertEqual(config.dch, "categorize")
        XCTAssertEqual(config.dc, "dg-category-marketing")
        XCTAssertEqual(config.privacyDomain, "api.consentjs.datagrailstaging.com")
        XCTAssertFalse(config.testMode)
        XCTAssertFalse(config.ignoreDoNotTrack)
        XCTAssertEqual(config.consentMode, "optout")
        XCTAssertFalse(config.showBanner)
        XCTAssertTrue(config.gppUsNat)

        // Verify plugins
        XCTAssertTrue(config.plugins.scriptControl)
        XCTAssertTrue(config.plugins.allCookieSubdomains)
        XCTAssertTrue(config.plugins.cookieBlocking)
        XCTAssertTrue(config.plugins.localStorageBlocking)
        XCTAssertFalse(config.plugins.syncOTConsent)

        // Verify consent policy
        XCTAssertEqual(config.consentPolicy.name, "CPRA")
        XCTAssertFalse(config.consentPolicy.default)

        // Verify initial categories
        XCTAssertTrue(config.initialCategories.respectGpc)
        XCTAssertTrue(config.initialCategories.respectDnt)
        XCTAssertFalse(config.initialCategories.respectOptout)
        XCTAssertEqual(config.initialCategories.initial.count, 4)
        XCTAssertTrue(config.initialCategories.initial.contains("dg-category-essential"))
        XCTAssertTrue(config.initialCategories.initial.contains("dg-category-marketing"))
        XCTAssertEqual(config.initialCategories.gpc.count, 1)
        XCTAssertEqual(config.initialCategories.gpc.first, "dg-category-essential")

        // Verify layout
        XCTAssertEqual(config.layout.id, "a788c60d-ec2c-40a9-bd3b-cfd371d62889")
        XCTAssertEqual(config.layout.name, "CPRA only")
        XCTAssertNil(config.layout.description)
        XCTAssertEqual(config.layout.status, "published")
        XCTAssertFalse(config.layout.defaultLayout)
        XCTAssertTrue(config.layout.collapsedOnMobile)
        XCTAssertEqual(config.layout.firstLayerId, "26259ccb-e5e0-4305-b696-fa2b7413c239")

        // Verify consent layers exist
        XCTAssertEqual(config.layout.consentLayers.count, 5)
        XCTAssertNotNil(config.layout.consentLayers["00a6e2c3-f1d5-4d3f-bd91-7d45cc0b75c5"])
        XCTAssertNotNil(config.layout.consentLayers["26259ccb-e5e0-4305-b696-fa2b7413c239"])
        XCTAssertNotNil(config.layout.consentLayers["b0b9fc31-4ea2-4026-8aa1-25fd647aa265"])
    }

    func testParseConfigBysFile() throws {
        // Load the config-bys.json from test resources (minified production config)
        guard let configUrl = Bundle.module.url(forResource: "config-bys", withExtension: "json")
        else {
            XCTFail("Could not find config-bys.json in test bundle")
            return
        }

        let configData = try Data(contentsOf: configUrl)

        // Parse the config
        let decoder = JSONDecoder()
        let config = try decoder.decode(ConsentConfig.self, from: configData)

        // Verify top-level properties
        XCTAssertEqual(config.version, "2709b618-15fa-4e08-bac0-2bb091c5b8c7")
        XCTAssertEqual(config.consentContainerVersionId, "bfd3f92e-79c2-4f8e-a31e-1dfe8a48a2d4")
        XCTAssertEqual(config.dgCustomerId, "ac46d8ad-a67a-431f-a5d5-9e3eb922dae7")
        XCTAssertEqual(config.publishDate, 1_769_205_191_913)
        XCTAssertEqual(config.dch, "categorize")
        XCTAssertEqual(config.dc, "dg-category-performance")
        XCTAssertEqual(config.privacyDomain, "api.consentjs.datagrailstaging.com")
        XCTAssertFalse(config.testMode)
        XCTAssertFalse(config.ignoreDoNotTrack)
        XCTAssertEqual(config.consentMode, "optout")
        XCTAssertFalse(config.showBanner)
        XCTAssertFalse(config.gppUsNat)

        // Verify plugins
        XCTAssertTrue(config.plugins.scriptControl)
        XCTAssertTrue(config.plugins.allCookieSubdomains)
        XCTAssertTrue(config.plugins.cookieBlocking)
        XCTAssertTrue(config.plugins.localStorageBlocking)
        XCTAssertFalse(config.plugins.syncOTConsent)

        // Verify consent policy
        XCTAssertEqual(config.consentPolicy.name, "US Standard Policy")
        XCTAssertFalse(config.consentPolicy.default)

        // Verify initial categories
        XCTAssertTrue(config.initialCategories.respectGpc)
        XCTAssertTrue(config.initialCategories.respectDnt)
        XCTAssertTrue(config.initialCategories.respectOptout)
        XCTAssertEqual(config.initialCategories.initial.count, 4)
        XCTAssertTrue(config.initialCategories.initial.contains("dg-category-essential"))
        XCTAssertTrue(config.initialCategories.initial.contains("dg-category-performance"))
        XCTAssertEqual(config.initialCategories.gpc.count, 1)
        XCTAssertEqual(config.initialCategories.gpc.first, "dg-category-essential")

        // Verify layout
        XCTAssertEqual(config.layout.id, "4ef6f04c-9cc8-4fa3-891f-40bf992e4cc0")
        XCTAssertEqual(config.layout.name, "Default Layout")
        XCTAssertEqual(config.layout.description, "Default Layout")
        XCTAssertEqual(config.layout.status, "published")
        XCTAssertTrue(config.layout.defaultLayout)
        XCTAssertFalse(config.layout.collapsedOnMobile)
        XCTAssertEqual(config.layout.firstLayerId, "3aa76c0a-8b18-4c70-b08f-6d3fe1d80f6c")
        XCTAssertEqual(config.layout.gpcDntLayerId, "19fcd340-6fb6-4363-bc9b-df10af839800")

        // Verify consent layers exist
        XCTAssertEqual(config.layout.consentLayers.count, 4)
        XCTAssertNotNil(config.layout.consentLayers["19fcd340-6fb6-4363-bc9b-df10af839800"])
        XCTAssertNotNil(config.layout.consentLayers["3aa76c0a-8b18-4c70-b08f-6d3fe1d80f6c"])
        XCTAssertNotNil(config.layout.consentLayers["44004606-fa0d-4103-be73-8ffe29f5ddd6"])
        XCTAssertNotNil(config.layout.consentLayers["977e9ba0-4ad2-4a4a-878e-b9f97a7412cd"])
    }

    func testParseCategoriesLayer() throws {
        guard let configUrl = Bundle.module.url(forResource: "test-config", withExtension: "json")
        else {
            XCTFail("Could not find test-config.json in test bundle")
            return
        }

        let configData = try Data(contentsOf: configUrl)
        let decoder = JSONDecoder()
        let config = try decoder.decode(ConsentConfig.self, from: configData)

        // Get the categories layer
        guard
            let categoriesLayer = config.layout.consentLayers[
                "26259ccb-e5e0-4305-b696-fa2b7413c239"]
        else {
            XCTFail("Categories layer not found")
            return
        }

        XCTAssertEqual(categoriesLayer.name, "Categories Ler")
        XCTAssertEqual(categoriesLayer.theme, "neutral")
        XCTAssertEqual(categoriesLayer.position, "left")
        XCTAssertTrue(categoriesLayer.showCloseButton)
        XCTAssertEqual(categoriesLayer.bannerApiId, "categories-layer")

        // Verify elements
        XCTAssertGreaterThan(categoriesLayer.elements.count, 0)

        // Find title element
        let titleElement = categoriesLayer.elements.first { element in
            element.type == "ConsentLayerTextElement" && element.style == "dg-title"
        }
        XCTAssertNotNil(titleElement)
        XCTAssertEqual(titleElement?.translations?["en"]?.value, "Privacy Settings")
    }

    func testParseDefaultLayer() throws {
        guard let configUrl = Bundle.module.url(forResource: "test-config", withExtension: "json")
        else {
            XCTFail("Could not find test-config.json in test bundle")
            return
        }

        let configData = try Data(contentsOf: configUrl)
        let decoder = JSONDecoder()
        let config = try decoder.decode(ConsentConfig.self, from: configData)

        // Get the default layer
        guard let defaultLayer = config.layout.consentLayers["b0b9fc31-4ea2-4026-8aa1-25fd647aa265"]
        else {
            XCTFail("Default layer not found")
            return
        }

        XCTAssertEqual(defaultLayer.name, "Default Layer")
        XCTAssertEqual(defaultLayer.position, "bottom")
        XCTAssertFalse(defaultLayer.showCloseButton)
        XCTAssertEqual(defaultLayer.bannerApiId, "default-layer")

        // Verify link element exists
        let linkElement = defaultLayer.elements.first { element in
            element.type == "ConsentLayerLinkElement"
        }
        XCTAssertNotNil(linkElement)
        XCTAssertEqual(linkElement?.links?.count, 2)

        // Verify Privacy Policy link
        let privacyLink = linkElement?.links?.first {
            $0.translations["en"]?.text == "Privacy Policy"
        }
        XCTAssertNotNil(privacyLink)
        XCTAssertEqual(
            privacyLink?.translations["en"]?.url, "https://www.datagrail.io/privacy-policy/")

        // Verify button element exists
        let buttonElement = defaultLayer.elements.first { element in
            element.type == "ConsentLayerButtonElement"
        }
        XCTAssertNotNil(buttonElement)
        XCTAssertEqual(buttonElement?.buttonAction, "open_layer")
        XCTAssertEqual(buttonElement?.targetConsentLayer, "00a6e2c3-f1d5-4d3f-bd91-7d45cc0b75c5")
        XCTAssertEqual(buttonElement?.translations?["en"]?.value, "OK")
    }

    func testParseAllLayerElements() throws {
        guard let configUrl = Bundle.module.url(forResource: "test-config", withExtension: "json")
        else {
            XCTFail("Could not find test-config.json in test bundle")
            return
        }

        let configData = try Data(contentsOf: configUrl)
        let decoder = JSONDecoder()
        let config = try decoder.decode(ConsentConfig.self, from: configData)

        // Iterate through all layers and verify all elements parse correctly
        for (layerId, layer) in config.layout.consentLayers {
            XCTAssertFalse(layer.id.isEmpty, "Layer \(layerId) should have an id")
            XCTAssertFalse(layer.name.isEmpty, "Layer \(layerId) should have a name")
            XCTAssertGreaterThan(layer.elements.count, 0, "Layer \(layerId) should have elements")

            for element in layer.elements {
                XCTAssertFalse(element.id.isEmpty, "Element should have an id")
                XCTAssertGreaterThan(element.order, 0, "Element should have order > 0")
                XCTAssertFalse(element.type.isEmpty, "Element should have a type")

                switch element.type {
                case "ConsentLayerTextElement":
                    XCTAssertNotNil(element.translations, "Text element should have translations")
                // Style is optional for text elements

                case "ConsentLayerButtonElement":
                    XCTAssertNotNil(element.translations, "Button element should have translations")
                    XCTAssertNotNil(
                        element.buttonAction, "Button element should have a button action")

                case "ConsentLayerLinkElement":
                    XCTAssertNotNil(element.links, "Link element should have links")
                    XCTAssertGreaterThan(
                        element.links?.count ?? 0,
                        0,
                        "Link element should have at least one link"
                    )

                case "ConsentLayerCategoryElement":
                    XCTAssertNotNil(
                        element.consentLayerCategories, "Category element should have categories")
                    XCTAssertGreaterThan(
                        element.consentLayerCategories?.count ?? 0,
                        0,
                        "Category element should have at least one category"
                    )

                default:
                    XCTFail("Unknown element type: \(element.type)")
                }
            }
        }
    }

    func testParseInvalidJSON() {
        let invalidJSON = "{ invalid json }"
        guard let data = invalidJSON.data(using: .utf8) else {
            XCTFail("Failed to create data from string")
            return
        }

        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode(ConsentConfig.self, from: data))
    }

    func testParseMissingRequiredFields() {
        let invalidConfig = """
            {
                "version": "test",
                "dgCustomerId": "test"
            }
            """
        guard let data = invalidConfig.data(using: .utf8) else {
            XCTFail("Failed to create data from string")
            return
        }

        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode(ConsentConfig.self, from: data))
    }
}
