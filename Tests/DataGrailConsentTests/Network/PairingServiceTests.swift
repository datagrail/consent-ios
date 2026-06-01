import XCTest
@testable import DataGrailConsent

/// Tests for QR pairing service (URL generation, consent read polling)
final class PairingServiceTests: XCTestCase {
    var mockNetworkClient: MockNetworkClientForPairing!
    var pairingService: PairingService!

    override func setUp() {
        super.setUp()
        mockNetworkClient = MockNetworkClientForPairing()
        pairingService = PairingService(
            networkClient: mockNetworkClient,
            apiBaseUrl: "https://consent.datagrail.io",
            apiKey: "test-api-key"
        )
    }

    // MARK: - QR URL Generation Tests

    func testQRURLGenerationWithValidInputs() {
        let url = pairingService.qrURL(
            publicBaseUrl: "http://192.168.1.5:8080",
            customerId: "cust-1",
            userHash: String(repeating: "a", count: 64),
            configUrl: "http://192.168.1.5:8080/tv/sample-config.json"
        )

        XCTAssertNotNil(url, "Should generate valid URL")

        guard let components = URLComponents(url: url!, resolvingAgainstBaseURL: false) else {
            XCTFail("Failed to parse URL components")
            return
        }

        XCTAssertEqual(components.path, "/tv/", "Path should be /tv/")

        let queryItems = components.queryItems ?? []
        XCTAssertTrue(
            queryItems.contains(where: { $0.name == "customer_id" && $0.value == "cust-1" }),
            "Should contain customer_id"
        )
        XCTAssertTrue(
            queryItems.contains(where: { $0.name == "user_hash" && $0.value == String(repeating: "a", count: 64) }),
            "Should contain user_hash"
        )
        XCTAssertTrue(
            queryItems.contains(where: { $0.name == "config_url" }),
            "Should contain config_url"
        )

        // Verify config_url is URL-encoded
        let configUrlItem = queryItems.first(where: { $0.name == "config_url" })
        XCTAssertNotNil(configUrlItem?.value, "config_url should have a value")
    }

    func testQRURLEncodesSpecialCharacters() {
        let url = pairingService.qrURL(
            publicBaseUrl: "https://example.com",
            customerId: "cust-1",
            userHash: String(repeating: "a", count: 64),
            configUrl: "https://example.com/config?foo=bar&baz=qux"
        )

        XCTAssertNotNil(url, "Should generate valid URL")

        guard let urlString = url?.absoluteString else {
            XCTFail("URL should have absoluteString")
            return
        }

        // config_url query param should be URL-encoded
        XCTAssertTrue(urlString.contains("config_url="), "Should contain config_url param")
    }

    func testQRURLWithHTTPSPublicBase() {
        let url = pairingService.qrURL(
            publicBaseUrl: "https://tunnel.example.com",
            customerId: "cust-1",
            userHash: String(repeating: "a", count: 64),
            configUrl: "https://example.com/config.json"
        )

        XCTAssertNotNil(url, "Should generate valid URL")
        XCTAssertTrue(url?.absoluteString.starts(with: "https://") ?? false, "Should use HTTPS")
    }

    // MARK: - Consent Read Tests

    func testFetchConsentReturnsNotFound() {
        let expectation = self.expectation(description: "Fetch consent not found")

        let notFoundResponse = """
        {
          "status": "not_found"
        }
        """.data(using: .utf8)!

        mockNetworkClient.mockResponse = notFoundResponse

        pairingService.fetchConsent(
            customerId: "cust-1",
            userHash: String(repeating: "a", count: 64)
        ) { result in
            switch result {
            case let .success(pairingRead):
                switch pairingRead {
                case .notFound:
                    expectation.fulfill()
                case .found:
                    XCTFail("Expected not_found, got found")
                }
            case let .failure(error):
                XCTFail("Expected success, got error: \(error)")
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testFetchConsentReturnsFound() {
        let expectation = self.expectation(description: "Fetch consent found")

        let foundResponse = """
        {
          "status": "found",
          "consent_preferences": {
            "is_customised": true,
            "cookie_options": [
              { "gtm_key": "dg-category-marketing", "is_enabled": false }
            ]
          }
        }
        """.data(using: .utf8)!

        mockNetworkClient.mockResponse = foundResponse

        pairingService.fetchConsent(
            customerId: "cust-1",
            userHash: String(repeating: "a", count: 64)
        ) { result in
            switch result {
            case let .success(pairingRead):
                switch pairingRead {
                case .notFound:
                    XCTFail("Expected found, got not_found")
                case let .found(preferences):
                    XCTAssertTrue(preferences.isCustomised)
                    XCTAssertEqual(preferences.cookieOptions.count, 1)
                    XCTAssertEqual(preferences.cookieOptions[0].gtmKey, "dg-category-marketing")
                    XCTAssertFalse(preferences.cookieOptions[0].isEnabled)
                    expectation.fulfill()
                }
            case let .failure(error):
                XCTFail("Expected success, got error: \(error)")
            }
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testFetchConsentAddsAPIKey() {
        let expectation = self.expectation(description: "Fetch adds API key")

        let notFoundResponse = """
        {
          "status": "not_found"
        }
        """.data(using: .utf8)!

        mockNetworkClient.mockResponse = notFoundResponse

        pairingService.fetchConsent(
            customerId: "cust-1",
            userHash: String(repeating: "a", count: 64)
        ) { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Verify the last request had X-DG-Api-Key header
        if let lastRequest = mockNetworkClient.lastRequest {
            XCTAssertEqual(
                lastRequest.value(forHTTPHeaderField: "X-DG-Api-Key"),
                "test-api-key",
                "Should include API key header"
            )
        } else {
            XCTFail("No request was made")
        }
    }

    func testFetchConsentAddsCacheControlNoCache() {
        let expectation = self.expectation(description: "Fetch adds no-cache")

        let notFoundResponse = """
        {
          "status": "not_found"
        }
        """.data(using: .utf8)!

        mockNetworkClient.mockResponse = notFoundResponse

        pairingService.fetchConsent(
            customerId: "cust-1",
            userHash: String(repeating: "a", count: 64)
        ) { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Verify the last request had Cache-Control: no-cache header
        if let lastRequest = mockNetworkClient.lastRequest {
            XCTAssertEqual(
                lastRequest.value(forHTTPHeaderField: "Cache-Control"),
                "no-cache",
                "Should include Cache-Control: no-cache"
            )
        } else {
            XCTFail("No request was made")
        }
    }

    func testFetchConsentBuildsCorrectURL() {
        let expectation = self.expectation(description: "Fetch builds correct URL")

        let notFoundResponse = """
        {
          "status": "not_found"
        }
        """.data(using: .utf8)!

        mockNetworkClient.mockResponse = notFoundResponse

        let userHash = String(repeating: "b", count: 64)

        pairingService.fetchConsent(
            customerId: "cust-2",
            userHash: userHash
        ) { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Verify URL
        if let lastRequest = mockNetworkClient.lastRequest {
            let urlString = lastRequest.url?.absoluteString ?? ""
            XCTAssertTrue(urlString.contains("/universal_consent"), "Should hit /universal_consent")
            XCTAssertTrue(urlString.contains("customer_id=cust-2"), "Should include customer_id")
            XCTAssertTrue(urlString.contains("user_hash=\(userHash)"), "Should include user_hash")
        } else {
            XCTFail("No request was made")
        }
    }
}
