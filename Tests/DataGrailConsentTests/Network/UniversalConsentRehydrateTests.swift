@testable import DataGrailConsent
import XCTest

/// Manager-level Universal Consent rehydration (TRUST-2491).
///
/// These exercise the acceptance criteria end to end: an identifier that consented on the web
/// resolves to that state on a fresh iOS install with no banner shown, and a read miss shows
/// the banner without writing an empty record.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class UniversalConsentRehydrateTests: XCTestCase {
    private var storage: ConsentStorage!
    private var mockNetworkClient: UCMockNetworkClient!
    private var sut: ConsentManager!
    private let testApiKey = "dg_live_test_key_123"
    private let privacyDomain = "consent.test.com"

    override func setUp() {
        super.setUp()
        storage = ConsentStorage()
        storage.clearAll()
        mockNetworkClient = UCMockNetworkClient()
        let configService = ConfigService(networkClient: mockNetworkClient, storage: storage)
        let consentService = ConsentService(
            networkClient: mockNetworkClient,
            storage: storage,
            privacyDomain: privacyDomain
        )
        sut = ConsentManager(
            storage: storage,
            configService: configService,
            consentService: consentService
        )
        loadUniversalConsentConfig()
    }

    override func tearDown() {
        storage.clearAll()
        sut = nil
        mockNetworkClient = nil
        storage = nil
        super.tearDown()
    }

    // MARK: - Acceptance: web consent resolves on a fresh install, no banner

    func testWebConsentRehydratesOnFreshInstallAndSuppressesBanner() {
        // Fresh install: nothing stored, so the banner would otherwise show.
        XCTAssertNil(storage.loadPreferences())
        XCTAssertTrue(sut.shouldDisplayBanner())

        mockNetworkClient.requestResult = .success(foundRecordJSON(marketing: true))
        let expectation = expectation(description: "rehydrate from web record")

        sut.rehydrateFromUniversalConsent(
            "user@example.com",
            apiKey: testApiKey,
            trackingSignal: .authorized
        ) { result in
            switch result {
            case let .success(rehydrated):
                XCTAssertTrue(rehydrated, "a found record must rehydrate local state")
            case let .failure(error):
                XCTFail("Expected success, got \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)

        // The web opt-in is now visible to every local read path...
        XCTAssertTrue(sut.isCategoryEnabled("dg-category-marketing"))
        XCTAssertTrue(sut.getCategories()?.isCategoryEnabled("dg-category-marketing") ?? false)
        // ...and the banner does not re-prompt a user who already answered elsewhere.
        XCTAssertFalse(sut.shouldDisplayBanner())
    }

    // MARK: - Acceptance: a miss shows the banner and writes nothing

    func testReadMissLeavesLocalStateEmptyAndKeepsBannerVisible() {
        mockNetworkClient.requestResult = .success(Data(#"{"status":"not_found"}"#.utf8))
        let expectation = expectation(description: "miss writes nothing")

        sut.rehydrateFromUniversalConsent(
            "user@example.com",
            apiKey: testApiKey,
            trackingSignal: .authorized
        ) { result in
            switch result {
            case let .success(rehydrated):
                XCTAssertFalse(rehydrated)
            case let .failure(error):
                XCTFail("A miss is not an error, got \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)

        // Nothing persisted: "no record" is the absence of a signal, not a denial. Writing an
        // empty record here would both fabricate a choice and hide the banner meant to collect it.
        XCTAssertNil(storage.loadPreferences())
        XCTAssertTrue(sut.shouldDisplayBanner())
    }

    // MARK: - Merge rule, both directions of disagreement

    /// Local says marketing OFF, remote says ON. The remote record is a real stored choice
    /// made by this same person on another device, and no signal is active, so it wins.
    func testRemoteOptInOverridesLocalOptOutWhenNoSignalApplies() {
        try? storage.savePreferences(ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "dg-category-essential", isEnabled: true),
                CategoryConsent(gtmKey: "dg-category-marketing", isEnabled: false),
            ]
        ))
        mockNetworkClient.requestResult = .success(foundRecordJSON(marketing: true))

        let expectation = expectation(description: "remote wins")
        sut.rehydrateFromUniversalConsent(
            "user@example.com",
            apiKey: testApiKey,
            trackingSignal: .authorized
        ) { _ in expectation.fulfill() }
        waitForExpectations(timeout: 1.0)

        XCTAssertTrue(sut.isCategoryEnabled("dg-category-marketing"))
    }

    /// Local says marketing ON, remote says OFF. Same rule, opposite direction: the stored
    /// remote record is authoritative, so rehydrating must turn the local value off rather
    /// than quietly keeping the more permissive of the two.
    func testRemoteOptOutOverridesLocalOptIn() {
        try? storage.savePreferences(ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "dg-category-essential", isEnabled: true),
                CategoryConsent(gtmKey: "dg-category-marketing", isEnabled: true),
            ]
        ))
        mockNetworkClient.requestResult = .success(foundRecordJSON(marketing: false))

        let expectation = expectation(description: "remote opt-out wins")
        sut.rehydrateFromUniversalConsent(
            "user@example.com",
            apiKey: testApiKey,
            trackingSignal: .authorized
        ) { _ in expectation.fulfill() }
        waitForExpectations(timeout: 1.0)

        XCTAssertFalse(sut.isCategoryEnabled("dg-category-marketing"))
    }

    // MARK: - Signals suppress the rehydrated state

    func testDeviceSignalSuppressesRehydratedMarketing() {
        mockNetworkClient.requestResult = .success(foundRecordJSON(marketing: true))
        let expectation = expectation(description: "ATT denied suppresses")

        sut.rehydrateFromUniversalConsent(
            "user@example.com",
            apiKey: testApiKey,
            trackingSignal: .denied
        ) { _ in expectation.fulfill() }
        waitForExpectations(timeout: 1.0)

        // Marketing was true in the stored record; this device says no tracking.
        XCTAssertFalse(sut.isCategoryEnabled("dg-category-marketing"))
        XCTAssertTrue(sut.isCategoryEnabled("dg-category-essential"))
    }

    /// iOS has no GPC of its own, so a web-recorded GPC reaches this device only via the
    /// record's stored field. Ignoring it would fire marketing for an opted-out user.
    func testStoredWebGpcSuppressesEvenWhenDeviceSignalIsPermissive() {
        mockNetworkClient.requestResult = .success(foundRecordJSON(marketing: true, gpc: true))
        let expectation = expectation(description: "stored gpc suppresses")

        sut.rehydrateFromUniversalConsent(
            "user@example.com",
            apiKey: testApiKey,
            trackingSignal: .authorized
        ) { _ in expectation.fulfill() }
        waitForExpectations(timeout: 1.0)

        XCTAssertFalse(sut.isCategoryEnabled("dg-category-marketing"))
        XCTAssertTrue(sut.isCategoryEnabled("dg-category-essential"))
    }

    // MARK: - Helpers

    private func loadUniversalConsentConfig() {
        guard let data = try? JSONEncoder().encode(UCFixtures.makeConfig(privacyDomain: privacyDomain)),
              let url = URL(string: "https://\(privacyDomain)/config.json")
        else {
            XCTFail("Failed to encode UC config fixture")
            return
        }

        mockNetworkClient.requestResult = .success(data)
        let expectation = expectation(description: "config loaded")
        sut.loadConfig(from: url) { result in
            if case let .failure(error) = result {
                XCTFail("Config load failed: \(error)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
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
          "platform": "web",
          "gpc": \(gpc)
        }
        """.utf8)
    }
}
