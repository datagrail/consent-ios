@testable import DataGrailConsent
import XCTest

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class UniversalConsentTests: XCTestCase {
    var mockNetworkClient: UCMockNetworkClient!
    var mockStorage: UCMockConsentStorage!
    var service: ConsentService!
    let testPrivacyDomain = "consent.test.com"
    let testApiKey = "dg_live_test_key_123"

    override func setUp() {
        super.setUp()
        mockNetworkClient = UCMockNetworkClient()
        mockStorage = UCMockConsentStorage()
        service = ConsentService(
            networkClient: mockNetworkClient,
            storage: mockStorage,
            privacyDomain: testPrivacyDomain
        )
    }

    override func tearDown() {
        service = nil
        mockStorage = nil
        mockNetworkClient = nil
        super.tearDown()
    }

    // Hashing and identifier-normalization coverage lives in UniversalConsentHashTests.

    // MARK: - Signal Reconciliation (mandatory, on-device)

    func testDeniedSignalSuppressesNonEssential() {
        // Stored map shows marketing:true — a client that trusts it naively would fire
        // marketing tags for a user who declined tracking. Effective must suppress it.
        let stored = ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "dg-category-essential", isEnabled: true),
                CategoryConsent(gtmKey: "dg-category-marketing", isEnabled: true),
                CategoryConsent(gtmKey: "dg-category-performance", isEnabled: true),
            ]
        )

        let effective = ConsentService.reconcile(
            preferences: stored,
            trackingSignal: .denied,
            essentialCategoryKeys: ["dg-category-essential"]
        )

        XCTAssertFalse(effective.isCategoryEnabled("dg-category-marketing"))
        XCTAssertFalse(effective.isCategoryEnabled("dg-category-performance"))
        XCTAssertTrue(effective.isCategoryEnabled("dg-category-essential"))
    }

    func testAuthorizedSignalLeavesPreferencesUntouched() {
        let stored = ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "dg-category-marketing", isEnabled: true),
            ]
        )

        let effective = ConsentService.reconcile(
            preferences: stored,
            trackingSignal: .authorized,
            essentialCategoryKeys: ["dg-category-essential"]
        )

        XCTAssertTrue(effective.isCategoryEnabled("dg-category-marketing"))
    }

    // MARK: - Signed POST attaches headers

    func testSetUserIdentifierAttachesSignedHeaders() {
        let expectation = expectation(description: "setUserIdentifier attaches headers")
        mockNetworkClient.requestResult = .success(Data())

        let provider: UniversalConsentSignatureProvider = { done in
            done(.success(UniversalConsentSignature(
                signature: "abc123sig",
                keyId: "key-1",
                timestamp: 1_720_000_000
            )))
        }

        service.setUserIdentifier(
            "user@example.com",
            preferences: marketingOnPreferences(),
            config: makeConfig(),
            apiKey: testApiKey,
            trackingSignal: .authorized,
            essentialCategoryKeys: ["dg-category-essential"],
            getSignature: provider
        ) { result in
            if case let .failure(error) = result {
                XCTFail("Expected success but got error: \(error)")
            }
            // POST to /universal_consent with the write headers, no /api/v1 prefix.
            XCTAssertEqual(self.mockNetworkClient.lastMethod, .post)
            XCTAssertTrue(
                self.mockNetworkClient.lastURL?.absoluteString.hasSuffix("/universal_consent") ?? false
            )
            XCTAssertFalse(
                self.mockNetworkClient.lastURL?.absoluteString.contains("/api/v1") ?? true
            )
            let headers = self.mockNetworkClient.lastHeaders ?? [:]
            // X-DG-Api-Key must be present on writes so the edge can locate the HMAC secret.
            XCTAssertEqual(headers["X-DG-Api-Key"], self.testApiKey)
            XCTAssertEqual(headers["X-DG-Signature"], "abc123sig")
            XCTAssertEqual(headers["X-DG-Key-Id"], "key-1")
            XCTAssertEqual(headers["X-DG-Timestamp"], "1720000000")
            XCTAssertNotNil(headers["X-DG-Nonce"])
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testSetUserIdentifierBodyCarriesHashAndCookieMap() {
        let expectation = expectation(description: "setUserIdentifier body shape")
        mockNetworkClient.requestResult = .success(Data())

        let provider: UniversalConsentSignatureProvider = { done in
            done(.success(UniversalConsentSignature(signature: "s", keyId: "k", timestamp: 1)))
        }

        service.setUserIdentifier(
            "user@example.com",
            preferences: marketingOnPreferences(),
            config: makeConfig(),
            apiKey: testApiKey,
            trackingSignal: .authorized,
            essentialCategoryKeys: ["dg-category-essential"],
            getSignature: provider
        ) { result in
            if case let .failure(error) = result {
                XCTFail("Expected success but got error: \(error)")
            }
            guard let body = self.mockNetworkClient.lastBody,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            else {
                XCTFail("Failed to parse request body")
                expectation.fulfill()
                return
            }
            XCTAssertEqual(
                json["user_hash"] as? String,
                "1fee132c298d615098190e3e75f9c7e05db20d6cff6398f686fcebc67d1d87a4"
            )
            XCTAssertEqual(json["customer_id"] as? String, "ac46d8ad-a67a-431f-a5d5-9e3eb922dae7")
            XCTAssertEqual(json["platform"] as? String, "ios")
            let prefs = json["consent_preferences"] as? [String: Any]
            let cookieOptions = prefs?["cookieOptions"] as? [String: Bool]
            XCTAssertNotNil(cookieOptions, "cookieOptions must be a MAP")
            XCTAssertEqual(cookieOptions?["dg-category-marketing"], true)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    private func marketingOnPreferences() -> ConsentPreferences {
        ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "dg-category-essential", isEnabled: true),
                CategoryConsent(gtmKey: "dg-category-marketing", isEnabled: true),
            ]
        )
    }

    func testSetUserIdentifierAppliesSignalBeforeWrite() {
        let expectation = expectation(description: "signal reconciled before write")
        mockNetworkClient.requestResult = .success(Data())

        let preferences = ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "dg-category-essential", isEnabled: true),
                CategoryConsent(gtmKey: "dg-category-marketing", isEnabled: true),
            ]
        )

        let provider: UniversalConsentSignatureProvider = { done in
            done(.success(UniversalConsentSignature(signature: "s", keyId: "k", timestamp: 1)))
        }

        service.setUserIdentifier(
            "user@example.com",
            preferences: preferences,
            config: makeConfig(),
            apiKey: testApiKey,
            trackingSignal: .denied,
            essentialCategoryKeys: ["dg-category-essential"],
            getSignature: provider
        ) { result in
            if case let .failure(error) = result {
                XCTFail("Expected success but got error: \(error)")
            }
            guard let body = self.mockNetworkClient.lastBody,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let prefs = json["consent_preferences"] as? [String: Any],
                  let cookieOptions = prefs["cookieOptions"] as? [String: Bool]
            else {
                XCTFail("Failed to parse request body")
                expectation.fulfill()
                return
            }
            // Marketing was true in store; the signal must suppress it in the payload.
            XCTAssertEqual(cookieOptions["dg-category-marketing"], false)
            XCTAssertEqual(cookieOptions["dg-category-essential"], true)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    // Hashing an empty normalized identifier yields SHA-256 of the bare tenant prefix —
    // a valid-looking hash shared by every such caller, which would collapse unrelated
    // users onto one consent record. "   " must be rejected too: it trims to nothing.

    func testSetUserIdentifierRejectsIdentifiersEmptyAfterNormalization() {
        for identifier in ["", "   ", "\t\n"] {
            let expectation = expectation(description: "empty identifier <\(identifier)> fails")

            let provider: UniversalConsentSignatureProvider = { done in
                done(.success(UniversalConsentSignature(signature: "s", keyId: "k", timestamp: 1)))
            }

            service.setUserIdentifier(
                identifier,
                preferences: ConsentPreferences(isCustomised: false, cookieOptions: []),
                config: makeConfig(),
                apiKey: testApiKey,
                getSignature: provider
            ) { result in
                switch result {
                case .success:
                    XCTFail("Expected failure for identifier <\(identifier)>")
                case .failure:
                    XCTAssertFalse(
                        self.mockNetworkClient.requestCalled,
                        "Must not hit network with an empty normalized identifier"
                    )
                }
                expectation.fulfill()
            }

            waitForExpectations(timeout: 1.0)
        }
    }

    /// An EMPTY projectId is as missing as a nil one — it would hash
    /// "{customerId}::{identifier}" and drop the project scope, merging one person's records
    /// across every project in the tenant. A published config with `"consentProjectId": ""`
    /// decodes to an empty string, not nil, so both cases have to be rejected.
    func testSetUserIdentifierFailsWithoutUsableProjectId() {
        for projectId: String? in [nil, "", "   "] {
            let expectation = expectation(description: "unusable projectId \(projectId ?? "nil") fails")

            var config = makeConfig()
            config.consentProjectId = projectId
            mockNetworkClient.requestCalled = false

            let provider: UniversalConsentSignatureProvider = { done in
                done(.success(UniversalConsentSignature(signature: "s", keyId: "k", timestamp: 1)))
            }

            service.setUserIdentifier(
                "user@example.com",
                preferences: ConsentPreferences(isCustomised: false, cookieOptions: []),
                config: config,
                apiKey: testApiKey,
                getSignature: provider
            ) { result in
                switch result {
                case .success:
                    XCTFail("Expected failure for consentProjectId \(projectId ?? "nil")")
                case .failure:
                    XCTAssertFalse(self.mockNetworkClient.requestCalled, "Must not hit network without projectId")
                }
                expectation.fulfill()
            }

            waitForExpectations(timeout: 1.0)
        }
    }

    func testSetUserIdentifierPropagatesSignatureFailure() {
        let expectation = expectation(description: "signature provider failure propagates")

        let provider: UniversalConsentSignatureProvider = { done in
            done(.failure(.networkError("backend down")))
        }

        service.setUserIdentifier(
            "user@example.com",
            preferences: ConsentPreferences(isCustomised: false, cookieOptions: []),
            config: makeConfig(),
            apiKey: testApiKey,
            getSignature: provider
        ) { result in
            switch result {
            case .success:
                XCTFail("Expected failure when signature provider fails")
            case .failure:
                XCTAssertFalse(self.mockNetworkClient.requestCalled, "Must not POST without a signature")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - Helpers

    private func makeConfig() -> ConsentConfig {
        UCFixtures.makeConfig(privacyDomain: testPrivacyDomain)
    }
}

// MARK: - Mocks

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class UCMockNetworkClient: NetworkClient {
    var requestCalled = false
    var requestResult: Result<Data, ConsentError> = .success(Data())
    var lastURL: URL?
    var lastMethod: HTTPMethod?
    var lastBody: Data?
    var lastHeaders: [String: String]?

    override func request(
        url: URL,
        method: HTTPMethod = .get,
        body: Data? = nil,
        headers: [String: String]? = nil,
        completion: @escaping (Result<Data, ConsentError>) -> Void
    ) {
        requestCalled = true
        lastURL = url
        lastMethod = method
        lastBody = body
        lastHeaders = headers
        completion(requestResult)
    }

    override func retryWithBackoff<T>(
        maxAttempts _: Int = 5,
        baseDelay _: TimeInterval = 0.25,
        operation: @escaping (@escaping (Result<T, ConsentError>) -> Void) -> Void,
        completion: @escaping (Result<T, ConsentError>) -> Void
    ) {
        // For testing, run the operation once without retry.
        operation(completion)
    }
}

final class UCMockConsentStorage: ConsentStorage {
    var uniqueId: String = "mock-unique-id"

    override func getOrCreateUniqueId() -> String {
        uniqueId
    }
}
