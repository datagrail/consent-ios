import XCTest

@testable import DataGrailConsent

/// TRUST-2603 — the edge API key can be delivered via config.json so it rotates server-side with
/// no client release. Covers the config decode of the new `apiKey` field and the precedence /
/// fail-fast resolution the public Universal Consent calls use.
final class UniversalConsentApiKeyConfigTests: XCTestCase {
    // MARK: - Config decode

    func testDecodesApiKeyFromUniversalConsentBlock() throws {
        let json = Data(
            """
            { "enabled": true, "sync_optout": false, "apiKey": "uc_live_abc123" }
            """.utf8
        )
        let config = try JSONDecoder().decode(UniversalConsentConfig.self, from: json)
        XCTAssertEqual(config.apiKey, "uc_live_abc123")
        XCTAssertTrue(config.enabled)
    }

    func testApiKeyIsNilWhenAbsentFromConfig() throws {
        let json = Data(#"{ "enabled": true, "sync_optout": false }"#.utf8)
        let config = try JSONDecoder().decode(UniversalConsentConfig.self, from: json)
        XCTAssertNil(config.apiKey)
    }

    // MARK: - Resolution precedence / fail-fast

    private func config(apiKey: String?) -> ConsentConfig {
        UCFixtures.makeConfig(universalApiKey: apiKey)
    }

    func testExplicitKeyWinsOverConfigValue() {
        let resolved = ConsentManager.resolveUniversalConsentApiKey(
            explicit: "explicit_key",
            in: config(apiKey: "config_key")
        )
        XCTAssertEqual(resolved, "explicit_key")
    }

    func testFallsBackToConfigKeyWhenExplicitIsNil() {
        let resolved = ConsentManager.resolveUniversalConsentApiKey(
            explicit: nil,
            in: config(apiKey: "config_key")
        )
        XCTAssertEqual(resolved, "config_key")
    }

    func testReturnsNilWhenNeitherPresent() {
        XCTAssertNil(
            ConsentManager.resolveUniversalConsentApiKey(explicit: nil, in: config(apiKey: nil))
        )
    }

    func testTreatsEmptyExplicitKeyAsAbsentAndFallsBack() {
        let resolved = ConsentManager.resolveUniversalConsentApiKey(
            explicit: "",
            in: config(apiKey: "config_key")
        )
        XCTAssertEqual(resolved, "config_key")
    }
}
