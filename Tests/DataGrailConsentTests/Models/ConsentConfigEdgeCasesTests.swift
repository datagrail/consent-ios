import XCTest

@testable import DataGrailConsent

final class ConsentConfigEdgeCasesTests: XCTestCase {
    func testParseConfigWithoutSyncOTConsent() throws {
        // Config where plugins does not include syncOTConsent field
        guard
            let configUrl = Bundle.module.url(forResource: "config-no-sync-ot", withExtension: "json")
        else {
            XCTFail("Could not find config-no-sync-ot.json in test bundle")
            return
        }

        let configData = try Data(contentsOf: configUrl)
        let decoder = JSONDecoder()
        let config = try decoder.decode(ConsentConfig.self, from: configData)

        // Verify top-level properties
        XCTAssertEqual(config.version, "0a3fa58e-6cae-4ba4-993f-7a6f844c553c")
        XCTAssertEqual(config.dgCustomerId, "ac46d8ad-a67a-431f-a5d5-9e3eb922dae7")
        XCTAssertEqual(config.publishDate, 1_772_640_197_596)
        XCTAssertEqual(config.dch, "categorize")
        XCTAssertEqual(config.dc, "dg-category-performance")
        XCTAssertEqual(config.consentMode, "optout")
        XCTAssertFalse(config.showBanner)
        XCTAssertTrue(config.gppUsNat)

        // Verify plugins - syncOTConsent defaults to false when absent
        XCTAssertTrue(config.plugins.scriptControl)
        XCTAssertTrue(config.plugins.allCookieSubdomains)
        XCTAssertTrue(config.plugins.cookieBlocking)
        XCTAssertTrue(config.plugins.localStorageBlocking)
        XCTAssertFalse(config.plugins.syncOTConsent)

        // Verify layout
        XCTAssertEqual(config.layout.id, "0c74436b-1c80-4078-89f8-e0840903252a")
        XCTAssertEqual(config.layout.name, "CPRA only")
        XCTAssertFalse(config.layout.defaultLayout)
        XCTAssertEqual(config.layout.gpcDntLayerId, "4de8260b-d70c-4601-9232-6d9631e49622")

        // Verify consent layers
        XCTAssertEqual(config.layout.consentLayers.count, 5)
    }

    func testParseConfigWithoutDc() throws {
        // Minimal config without the optional "dc" field
        let configWithoutDc = """
            {
                "version": "test-version",
                "consentContainerVersionId": "test-container-id",
                "dgCustomerId": "test-customer-id",
                "p": 1234567890,
                "dch": "categorize",
                "privacyDomain": "test.example.com",
                "plugins": {
                    "scriptControl": true,
                    "allCookieSubdomains": true,
                    "cookieBlocking": true,
                    "localStorageBlocking": true
                },
                "testMode": false,
                "ignoreDoNotTrack": false,
                "trackingDetailsUrl": "https://test.example.com/tracking.json",
                "consentMode": "optout",
                "showBanner": false,
                "consentPolicy": {
                    "name": "Test Policy",
                    "default": false
                },
                "gppUsNat": false,
                "initialCategories": {
                    "respect_gpc": false,
                    "respect_dnt": false,
                    "respect_optout": false,
                    "initial": [],
                    "gpc": [],
                    "optout": []
                },
                "layout": {
                    "id": "test-layout-id",
                    "name": "Test Layout",
                    "description": null,
                    "status": "published",
                    "default_layout": false,
                    "collapsed_on_mobile": false,
                    "first_layer_id": "test-layer-id",
                    "consent_layers": {}
                }
            }
            """
        guard let data = configWithoutDc.data(using: .utf8) else {
            XCTFail("Failed to create data from string")
            return
        }

        let decoder = JSONDecoder()
        let config = try decoder.decode(ConsentConfig.self, from: data)

        // Verify the config decoded successfully and dc is nil
        XCTAssertNil(config.dc, "dc field should be nil when omitted from JSON")
        XCTAssertEqual(config.version, "test-version")
        XCTAssertEqual(config.dch, "categorize")
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
