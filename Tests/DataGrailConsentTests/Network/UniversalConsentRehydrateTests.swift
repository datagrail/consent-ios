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

    // MARK: - Rehydration persists the reconciled view but hands back the raw one

    /// The read-then-write flow's core invariant, and the reason
    /// ``ConsentManager/rehydrateReturningRawPreferences(_:apiKey:trackingSignal:completion:)``
    /// exists at all.
    ///
    /// Rehydration deliberately persists the SUPPRESSED state locally — that is what makes
    /// `isCategoryEnabled` honor the device signal. But the write that follows must carry the
    /// user's real choice. Sourcing it from `getCategories()` after rehydration would read back
    /// the suppression and store it as consent, erasing a web opt-in for every device on the
    /// identifier the first time the app opens with ATT denied.
    func testRehydrateReturnsRawPreferencesWhileStoringSuppressedOnes() {
        mockNetworkClient.requestResult = .success(foundRecordJSON(marketing: true))
        let expectation = expectation(description: "raw returned, suppressed stored")

        var rawPreferences: ConsentPreferences?
        sut.rehydrateReturningRawPreferences(
            "user@example.com",
            apiKey: testApiKey,
            trackingSignal: .denied
        ) { result in
            rawPreferences = try? result.get()
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        // Handed back to the write path: the user's actual opt-in.
        XCTAssertEqual(rawPreferences?.isCategoryEnabled("dg-category-marketing"), true)
        // Persisted locally: the suppressed view, so reads honor the device signal.
        XCTAssertFalse(sut.isCategoryEnabled("dg-category-marketing"))
        XCTAssertTrue(sut.isCategoryEnabled("dg-category-essential"))
    }

    func testRehydrateReturnsNilOnAMiss() {
        mockNetworkClient.requestResult = .success(Data(#"{"status":"not_found"}"#.utf8))
        let expectation = expectation(description: "miss returns nil")

        var result: Result<ConsentPreferences?, ConsentError>?
        sut.rehydrateReturningRawPreferences(
            "user@example.com",
            apiKey: testApiKey,
            trackingSignal: .authorized
        ) {
            result = $0
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        // A miss is the absence of a signal, not a denial — a success carrying nil, nothing
        // to write, nothing stored.
        if case let .success(preferences) = result {
            XCTAssertNil(preferences, "a miss returns success(nil), not a fabricated record")
        } else {
            XCTFail("A miss is not an error, got \(String(describing: result))")
        }
        XCTAssertNil(storage.loadPreferences())
    }

    // MARK: - A found record answered with zero non-essential categories is still an answer

    func testFoundRecordWithEmptyCookieOptionsRehydratesAndSuppressesBanner() {
        XCTAssertTrue(sut.shouldDisplayBanner())
        mockNetworkClient.requestResult = .success(Data(#"""
        {"status":"found","consent_preferences":{"isCustomised":true,"cookieOptions":{}},"gpc":false}
        """#.utf8))

        let expectation = expectation(description: "empty-map record rehydrates")
        sut.rehydrateFromUniversalConsent(
            "user@example.com",
            apiKey: testApiKey,
            trackingSignal: .authorized
        ) { result in
            switch result {
            case let .success(rehydrated):
                XCTAssertTrue(rehydrated, "a found record with zero non-essential categories is still an answer")
            case let .failure(error):
                XCTFail("Expected success, got \(error)")
            }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        // A present-but-empty cookieOptions map is a found record, not a miss. Local state now
        // exists, so the banner does not re-prompt a user who already answered elsewhere.
        XCTAssertNotNil(storage.loadPreferences())
        XCTAssertFalse(sut.shouldDisplayBanner())
    }

    // MARK: - A signal-only found record (no consent_preferences) must not fabricate an answer

    /// A record can exist for the gpc/ccpa signal alone, carrying NO `consent_preferences` — the
    /// user left a signal on the web but never actually answered a consent prompt. Fabricating an
    /// answer from it (isCustomised:true + empty map) would suppress the banner forever and read
    /// every category, essential included, as disabled for a user who never chose. It must behave
    /// like a not-yet-answered user: nothing persisted, so the banner still shows.
    func testSignalOnlyRecordDoesNotFabricateAnswerOrSuppressBanner() {
        XCTAssertTrue(sut.shouldDisplayBanner())
        mockNetworkClient.requestResult = .success(Data(#"{"status":"found","gpc":true}"#.utf8))

        let expectation = expectation(description: "signal-only record")
        var result: Result<ConsentPreferences?, ConsentError>?
        sut.rehydrateReturningRawPreferences(
            "user@example.com",
            apiKey: testApiKey,
            trackingSignal: .authorized
        ) {
            result = $0
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        // No consent choices to hand back to the write path.
        if case let .success(preferences) = result {
            XCTAssertNil(preferences, "a signal-only record carries no consent choice to write")
        } else {
            XCTFail("A signal-only record is not an error, got \(String(describing: result))")
        }
        // Nothing persisted, so the user who never answered still sees the banner and no category
        // is forced to disabled by a fabricated empty record.
        XCTAssertNil(storage.loadPreferences())
        XCTAssertTrue(sut.shouldDisplayBanner())
    }

    // MARK: - A caller who never recorded a choice must not sync a fabricated default

    func testSetUserIdentifierWithoutAChoiceDoesNotWriteFabricatedDefault() {
        // Fresh install: the user never answered a banner, so there is no stored choice and
        // no preferences are passed in.
        XCTAssertNil(storage.loadPreferences())
        mockNetworkClient.requestCalled = false

        let expectation = expectation(description: "no write without a choice")
        sut.setUserIdentifier("user@example.com", apiKey: testApiKey) { result in
            switch result {
            case .success:
                XCTFail("Must not sync a fabricated default for a user who never answered")
            case let .failure(error):
                guard case .invalidConfiguration = error else {
                    return XCTFail("Expected invalidConfiguration, got \(error)")
                }
            }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        // The default (isCustomised: false) was never POSTed to the cross-device store — which
        // would otherwise mark the identifier answered and hide the banner forever.
        XCTAssertFalse(mockNetworkClient.requestCalled)
        XCTAssertNil(storage.loadPreferences())
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

// MARK: - Write-through: sync the local choice, never re-POST the fetched record

// In an extension so the primary test class stays within SwiftLint's type_body_length limit.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension UniversalConsentRehydrateTests {

    /// On a found record the write must carry the user's CURRENT LOCAL choice (sync-on-change),
    /// not the record it just fetched. Re-POSTing the fetched map would discard a local opt-out
    /// the user made on this device before associating their identity — and echo state the edge
    /// already holds.
    func testSyncWritesLocalRawChoiceNotTheFetchedRecordOnAHit() {
        // The user opted marketing OFF locally before associating their identity.
        try? storage.savePreferences(ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "dg-category-essential", isEnabled: true),
                CategoryConsent(gtmKey: "dg-category-marketing", isEnabled: false),
            ]
        ))
        // The stored record disagrees (marketing ON).
        mockNetworkClient.requestResult = .success(foundRecordJSON(marketing: true))

        let expectation = expectation(description: "write-through local choice")
        sut.syncUserIdentifier(
            "user@example.com",
            apiKey: testApiKey,
            trackingSignal: .authorized
        ) { result in
            if case let .failure(error) = result {
                XCTFail("Expected success, got \(error)")
            }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        // The last request is the WRITE, and it carries the LOCAL choice (marketing OFF) — NOT
        // the fetched record (marketing ON).
        XCTAssertEqual(mockNetworkClient.lastMethod, .post)
        guard let body = mockNetworkClient.lastBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let prefs = json["consent_preferences"] as? [String: Any],
              let cookieOptions = prefs["cookieOptions"] as? [String: Bool]
        else {
            return XCTFail("Failed to parse write body")
        }
        XCTAssertEqual(cookieOptions["dg-category-marketing"], false, "write carries the LOCAL choice")

        // Local reads still reflect the record — remote wins for the read side.
        XCTAssertTrue(sut.isCategoryEnabled("dg-category-marketing"))
    }

    /// A found record with no local change is adopted into local state and NOT re-POSTed. The
    /// only request is the GET; a trailing write would clobber a richer server record with this
    /// fresh install's defaults, or pointlessly echo state the edge already holds.
    func testSyncAdoptsWithoutPostWhenThereIsNoLocalChoice() {
        XCTAssertNil(storage.loadPreferences())
        mockNetworkClient.requestResult = .success(foundRecordJSON(marketing: true))

        let expectation = expectation(description: "adopt without post")
        sut.syncUserIdentifier(
            "user@example.com",
            apiKey: testApiKey,
            trackingSignal: .authorized
        ) { result in
            if case let .failure(error) = result {
                XCTFail("Expected success, got \(error)")
            }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        // The record was adopted into local state...
        XCTAssertTrue(sut.isCategoryEnabled("dg-category-marketing"))
        XCTAssertFalse(sut.shouldDisplayBanner())
        // ...but nothing was POSTed: the last (and only) request was the GET.
        XCTAssertEqual(
            mockNetworkClient.lastMethod,
            .get,
            "a found record with no local change is adopted, not re-POSTed"
        )
    }

    /// A miss with a local choice seeds the first cross-device record, and the write carries the
    /// RAW choice: a device signal (here ATT denied) suppresses local reads but must never be
    /// folded into the cross-device store, or a later session without the signal reads it back as
    /// a revocation the user never made.
    func testSyncWritesRawLocalChoiceWithoutFoldingTheDeviceSignal() {
        try? storage.savePreferences(ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "dg-category-essential", isEnabled: true),
                CategoryConsent(gtmKey: "dg-category-marketing", isEnabled: true),
            ]
        ))
        mockNetworkClient.requestResult = .success(Data(#"{"status":"not_found"}"#.utf8))

        let expectation = expectation(description: "seed raw choice, signal not folded")
        sut.syncUserIdentifier(
            "user@example.com",
            apiKey: testApiKey,
            trackingSignal: .denied
        ) { result in
            if case let .failure(error) = result {
                XCTFail("Expected success, got \(error)")
            }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(mockNetworkClient.lastMethod, .post)
        guard let body = mockNetworkClient.lastBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let prefs = json["consent_preferences"] as? [String: Any],
              let cookieOptions = prefs["cookieOptions"] as? [String: Bool]
        else {
            return XCTFail("Failed to parse write body")
        }
        XCTAssertEqual(cookieOptions["dg-category-marketing"], true, "raw local choice, signal not folded")
    }
}
