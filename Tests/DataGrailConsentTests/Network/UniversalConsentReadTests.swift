@testable import DataGrailConsent
import XCTest

/// Universal Consent READ path (TRUST-2491).
///
/// Split from `UniversalConsentTests` (the write path) to keep both suites under SwiftLint's
/// `type_body_length` limit.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class UniversalConsentReadTests: XCTestCase {
    private var mockNetworkClient: UCMockNetworkClient!
    private var mockStorage: UCMockConsentStorage!
    private var service: ConsentService!
    private let testPrivacyDomain = "consent.test.com"
    private let testApiKey = "dg_live_test_key_123"
    private let goldenHash = "1fee132c298d615098190e3e75f9c7e05db20d6cff6398f686fcebc67d1d87a4"

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

    // MARK: - Request shape

    func testGetUniversalConsentIssuesGetWithHashAndApiKey() {
        let expectation = expectation(description: "GET request shape")
        mockNetworkClient.requestResult = .success(foundRecordJSON(marketing: true))

        service.getUniversalConsent(
            "user@example.com",
            config: makeConfig(),
            apiKey: testApiKey
        ) { _ in
            XCTAssertEqual(self.mockNetworkClient.lastMethod, .get)
            XCTAssertNil(self.mockNetworkClient.lastBody, "A read must not carry a body")

            let url = self.mockNetworkClient.lastURL?.absoluteString ?? ""
            XCTAssertTrue(url.contains("/universal_consent"))
            // CloudFront behavior, not a Rails route — no /api/v1 prefix.
            XCTAssertFalse(url.contains("/api/v1"))
            XCTAssertTrue(
                url.contains("user_hash=\(self.goldenHash)"),
                "read must query the same golden hash the write path posts: \(url)"
            )
            XCTAssertTrue(url.contains("customer_id=\(UCFixtures.customerId)"))

            // Reads are unsigned, but the API key is still required so the edge can resolve
            // the customer from KVS.
            let headers = self.mockNetworkClient.lastHeaders ?? [:]
            XCTAssertEqual(headers["X-DG-Api-Key"], self.testApiKey)
            XCTAssertNil(headers["X-DG-Signature"])
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    /// The read path hashes the identifier exactly as the write path does. If these ever
    /// diverge, a user writes to one record and reads from another — consent silently stops
    /// following them, with no error anywhere.
    func testReadHashMatchesWriteHashForMessyIdentifier() {
        let expectation = expectation(description: "read normalizes identifier")
        mockNetworkClient.requestResult = .success(notFoundJSON())

        service.getUniversalConsent(
            "  User@Example.com  ",
            config: makeConfig(),
            apiKey: testApiKey
        ) { _ in
            XCTAssertTrue(
                self.mockNetworkClient.lastURL?.absoluteString.contains("user_hash=\(self.goldenHash)") ?? false
            )
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - Miss is not a denial

    func testNotFoundYieldsNilRatherThanEmptyRecord() {
        let expectation = expectation(description: "not_found maps to nil")
        mockNetworkClient.requestResult = .success(notFoundJSON())

        service.getUniversalConsent(
            "user@example.com",
            config: makeConfig(),
            apiKey: testApiKey
        ) { result in
            switch result {
            case let .success(record):
                // nil, not an all-false record: a miss means "no signal", and the banner
                // decision for "no signal" is the opposite of the one for "denied".
                XCTAssertNil(record)
            case let .failure(error):
                XCTFail("Expected success, got \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    /// A `not_found` body carries neither `consent_preferences` nor `cookieOptions`. Swift's
    /// synthesized decoder throws on missing keys rather than using property defaults, so
    /// this would surface as a parse error without the custom decoders.
    func testMinimalNotFoundBodyDecodesWithoutThrowing() {
        let expectation = expectation(description: "minimal body decodes")
        mockNetworkClient.requestResult = .success(Data(#"{"status":"not_found"}"#.utf8))

        service.getUniversalConsent(
            "user@example.com",
            config: makeConfig(),
            apiKey: testApiKey
        ) { result in
            if case let .failure(error) = result {
                XCTFail("Minimal not_found body must decode, got \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - Preconditions (must not hit the network)

    func testGetRejectsIdentifiersEmptyAfterNormalization() {
        // On a READ this matters as much as on a write: the bare-tenant-prefix hash is shared
        // by every empty caller, so it would hand back an unrelated user's record.
        for identifier in ["", "   ", "\t\n"] {
            let expectation = expectation(description: "empty identifier <\(identifier)> fails")
            mockNetworkClient.requestCalled = false

            service.getUniversalConsent(
                identifier,
                config: makeConfig(),
                apiKey: testApiKey
            ) { result in
                switch result {
                case .success:
                    XCTFail("Expected failure for identifier <\(identifier)>")
                case .failure:
                    XCTAssertFalse(self.mockNetworkClient.requestCalled, "Must not read with an empty hash input")
                }
                expectation.fulfill()
            }

            waitForExpectations(timeout: 1.0)
        }
    }

    func testGetFailsWithoutUsableProjectId() {
        for projectId: String? in [nil, "", "   "] {
            let expectation = expectation(description: "unusable projectId \(projectId ?? "nil") fails")
            var config = makeConfig()
            config.consentProjectId = projectId
            mockNetworkClient.requestCalled = false

            service.getUniversalConsent(
                "user@example.com",
                config: config,
                apiKey: testApiKey
            ) { result in
                switch result {
                case .success:
                    XCTFail("Expected failure for consentProjectId \(projectId ?? "nil")")
                case .failure:
                    XCTAssertFalse(self.mockNetworkClient.requestCalled)
                }
                expectation.fulfill()
            }

            waitForExpectations(timeout: 1.0)
        }
    }

    func testGetHonorsFeatureGate() {
        let expectation = expectation(description: "disabled UC fails the read")
        var config = makeConfig()
        config.universalConsent = UniversalConsentConfig(enabled: false, syncOptout: false)

        service.getUniversalConsent(
            "user@example.com",
            config: config,
            apiKey: testApiKey
        ) { result in
            switch result {
            case .success:
                XCTFail("Expected failure when Universal Consent is disabled")
            case .failure:
                XCTAssertFalse(self.mockNetworkClient.requestCalled)
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - Reconciliation of the read (map overload)

    func testStoredGpcSuppressesNonEssentialOnRead() {
        // The record was written on the web with GPC active. iOS has no GPC of its own, so
        // the ONLY way this device learns about it is the stored field — ignoring it would
        // fire marketing tags for a user who signalled do-not-sell.
        let reconciled = ConsentService.reconcile(
            cookieOptions: [
                "dg-category-essential": true,
                "dg-category-marketing": true,
                "dg-category-performance": true,
            ],
            suppress: true,
            essentialCategoryKeys: ["dg-category-essential"]
        )

        XCTAssertEqual(reconciled["dg-category-marketing"], false)
        XCTAssertEqual(reconciled["dg-category-performance"], false)
        XCTAssertEqual(reconciled["dg-category-essential"], true)
    }

    func testNoSignalLeavesStoredMapUntouched() {
        let stored = ["dg-category-marketing": true, "dg-category-essential": true]
        XCTAssertEqual(
            ConsentService.reconcile(
                cookieOptions: stored,
                suppress: false,
                essentialCategoryKeys: ["dg-category-essential"]
            ),
            stored
        )
    }

    /// Suppression is one-directional. No signal state may turn a stored `false` into `true`
    /// — that would manufacture consent the user never gave.
    func testReconcileNeverEnablesADisabledCategory() {
        let stored = ["dg-category-essential": true, "dg-category-marketing": false]

        for suppress in [true, false] {
            let reconciled = ConsentService.reconcile(
                cookieOptions: stored,
                suppress: suppress,
                essentialCategoryKeys: ["dg-category-essential"]
            )
            XCTAssertEqual(
                reconciled["dg-category-marketing"], false,
                "suppress=\(suppress) must not enable a category the user turned off"
            )
        }
    }

    /// Essential is always on. A record that omits an essential key entirely (older or
    /// signal-shaped record) must still resolve it to enabled — never let it fall through to
    /// disabled after rehydration, with or without a suppressing signal.
    func testReconcileBackfillsMissingEssentialCategory() {
        for suppress in [true, false] {
            let reconciled = ConsentService.reconcile(
                cookieOptions: ["dg-category-marketing": true],
                suppress: suppress,
                essentialCategoryKeys: ["dg-category-essential"]
            )
            XCTAssertEqual(
                reconciled["dg-category-essential"], true,
                "suppress=\(suppress) must backfill a missing essential category to enabled"
            )
        }
    }

    /// An essential key stored as `false` in the record must still resolve to enabled — essential
    /// is always on regardless of the stored value.
    func testReconcileForcesStoredEssentialOn() {
        let reconciled = ConsentService.reconcile(
            cookieOptions: ["dg-category-essential": false, "dg-category-marketing": true],
            suppress: false,
            essentialCategoryKeys: ["dg-category-essential"]
        )
        XCTAssertEqual(reconciled["dg-category-essential"], true)
    }

    /// The suppress decision is centralized so `fetchUniversalConsent` and
    /// `rehydrateReturningRawPreferences` cannot diverge. Lock its truth table: either the
    /// record's stored `gpc` or a suppressing tracking signal is enough, and only when both
    /// are permissive does it not suppress.
    func testSuppressesCombinesStoredGpcAndTrackingSignal() {
        func record(gpc: Bool = false, ccpaOptout: Bool = false) -> UniversalConsentRecord {
            UniversalConsentRecord(status: "found", ccpaOptout: ccpaOptout, gpc: gpc)
        }

        XCTAssertFalse(
            ConsentService.suppresses(record: record(), trackingSignal: .authorized),
            "no signal suppresses"
        )
        XCTAssertTrue(
            ConsentService.suppresses(record: record(gpc: true), trackingSignal: .authorized),
            "stored gpc alone suppresses"
        )
        XCTAssertTrue(
            ConsentService.suppresses(record: record(ccpaOptout: true), trackingSignal: .authorized),
            "stored CCPA opt-out alone suppresses"
        )
        XCTAssertTrue(
            ConsentService.suppresses(record: record(), trackingSignal: .denied),
            "tracking signal alone suppresses"
        )
        XCTAssertTrue(
            ConsentService.suppresses(record: record(gpc: true, ccpaOptout: true), trackingSignal: .denied),
            "all suppress"
        )
    }

    // MARK: - Helpers

    private func makeConfig() -> ConsentConfig {
        UCFixtures.makeConfig(privacyDomain: testPrivacyDomain)
    }

    private func foundRecordJSON(marketing: Bool, gpc: Bool = false) -> Data {
        Data("""
        {
          "status": "found",
          "consent_preferences": {
            "isCustomised": true,
            "cookieOptions": {
              "dg-category-essential": true,
              "dg-category-marketing": \(marketing)
            }
          },
          "consent_mode": "optin",
          "ccpa_optout": false,
          "platform": "web",
          "gpc": \(gpc)
        }
        """.utf8)
    }

    private func notFoundJSON() -> Data {
        Data(#"{"status":"not_found","ccpa_optout":false,"gpc":false}"#.utf8)
    }
}
