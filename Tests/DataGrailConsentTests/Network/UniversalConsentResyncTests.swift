@testable import DataGrailConsent
import XCTest

/// A same-identity re-sync (TRUST-2902): with nothing changed on this device since the last sync,
/// the record is adopted and nothing is written, also after an app relaunch; a user change is
/// written as the user's raw choice. The edge stamps every write with its write time, so re-sending
/// a choice the user did not change would beat a newer choice made on another device.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class UniversalConsentResyncTests: XCTestCase {
    private var storage: ConsentStorage!
    private var network: MethodAwareMockNetworkClient!
    private var sut: ConsentManager!
    private let testApiKey = "dg_live_test_key_123"
    private let privacyDomain = "consent.test.com"
    private let userA = "alice@example.com"
    private let userB = "bob@example.com"

    override func setUp() {
        super.setUp()
        storage = ConsentStorage()
        storage.clearAll()
        relaunch()
    }

    override func tearDown() {
        storage.clearAll()
        sut = nil
        network = nil
        storage = nil
        super.tearDown()
    }

    // MARK: - Nothing changed on this device

    func testUnchangedResyncAdoptsAnotherDevicesNewerChoiceWithoutWriting() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA).get())

        // Another device turned marketing off since.
        network.getResult = .success(foundRecordJSON(marketing: false))
        XCTAssertNoThrow(try sync(userA).get())

        XCTAssertEqual(network.methods, [.get, .get], "an unchanged choice is never re-sent")
        XCTAssertNil(network.lastPostBody)
        XCTAssertEqual(storedMarketing(), false, "local takes the record's newer value")
    }

    func testUnchangedResyncAfterARelaunchWritesNothing() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA).get())

        relaunch()
        network.getResult = .success(foundRecordJSON(marketing: false))
        XCTAssertNoThrow(try sync(userA).get())

        XCTAssertEqual(network.methods, [.get], "no POST after the relaunch either")
        XCTAssertNil(network.lastPostBody)
        XCTAssertEqual(storedMarketing(), false, "local takes the record's newer value")
    }

    func testATTSuppressedViewIsNotWrittenByAResyncAfterARelaunch() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA, trackingSignal: .denied).get())
        XCTAssertEqual(storedMarketing(), false, "local state holds the ATT-suppressed view")

        relaunch()
        XCTAssertNoThrow(try sync(userA, trackingSignal: .denied).get())
        relaunch()
        XCTAssertNoThrow(try sync(userA, trackingSignal: .denied).get())

        XCTAssertEqual(network.methods, [.get], "the suppressed map is never written")
        XCTAssertNil(network.lastPostBody)
        XCTAssertEqual(storedMarketing(), false)
    }

    func testSetterAfterAnUnchangedResyncAfterARelaunchWritesTheRecordsRawOptIn() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA, trackingSignal: .denied).get())

        relaunch()
        XCTAssertNoThrow(try sync(userA, trackingSignal: .denied).get())
        XCTAssertNoThrow(try setCcpaOptout(true).get())

        XCTAssertEqual(network.methods, [.get, .post])
        XCTAssertEqual(writtenCookieOptions()?["dg-category-marketing"], true, "the record's raw opt-in")
    }

    // MARK: - The user changed something

    func testUserChangeThenResyncAfterARelaunchWritesTheRawChoice() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA, trackingSignal: .denied).get())
        try save(choice(marketing: true, analytics: false))

        relaunch()
        XCTAssertNoThrow(try sync(userA, trackingSignal: .denied).get())

        XCTAssertEqual(network.methods, [.get, .post])
        XCTAssertEqual(writtenCookieOptions(), [
            "dg-category-essential": true,
            "dg-category-marketing": true,
            "dg-category-analytics": false,
        ], "the user's raw saved choice; ATT only shapes local state")
    }

    func testSaveDuringAnInFlightWriteIsWrittenByTheNextResync() throws {
        try storage.savePreferences(choice(marketing: true, analytics: true))
        network.getResult = .success(notFound)
        network.deferPost = true
        var outcome: Result<Void, ConsentError>?
        sut.syncUserIdentifier(userA, apiKey: testApiKey, trackingSignal: .authorized) { outcome = $0 }
        let completeSeedWrite = try XCTUnwrap(network.pendingPostCompletion)

        // The user saves a new choice while the seed write is in flight.
        network.deferPost = false
        try save(choice(marketing: false, analytics: true))
        completeSeedWrite(network.postResult)
        XCTAssertNoThrow(try XCTUnwrap(outcome).get())

        network.getResult = .success(foundRecordJSON(marketing: true, analytics: true))
        network.methods = []
        XCTAssertNoThrow(try sync(userA).get())

        XCTAssertEqual(network.methods, [.get, .post], "the mid-write save is a change")
        XCTAssertEqual(writtenCookieOptions()?["dg-category-marketing"], false)
    }

    // MARK: - The persisted session's lifetime

    func testLogoutClearsThePersistedSyncState() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA).get())
        XCTAssertEqual(storage.loadSyncState()?.userHash, try hash(userA))

        sut.clearUserIdentifier()

        XCTAssertNil(storage.loadSyncState())
    }

    func testResetClearsThePersistedSyncState() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA).get())

        sut.reset()

        XCTAssertNil(storage.loadSyncState())
    }

    func testIdentitySwitchReplacesThePersistedSyncState() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA).get())

        network.getResult = .success(notFound)
        XCTAssertNoThrow(try sync(userB).get())

        XCTAssertEqual(storage.loadBoundUserHash(), try hash(userB))
        let state = try XCTUnwrap(storage.loadSyncState())
        XCTAssertEqual(state.userHash, try hash(userB), "user A's sync state is replaced")
        XCTAssertNil(state.syncedLocal, "A's state returned to neutral; nothing of it is kept")
        XCTAssertNil(state.syncedRaw)
    }

    func testSyncStateForAnotherIdentityIsDroppedOnLaunch() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA).get())
        storage.saveBoundUserHash(try hash(userB))

        relaunch()

        XCTAssertNil(storage.loadSyncState())
    }

    // MARK: - Helpers

    private let notFound = Data(#"{"status":"not_found"}"#.utf8)

    /// Build a fresh manager over the same storage, as an app relaunch does. The new network keeps
    /// serving the record the old one served.
    private func relaunch() {
        let servedRecord = network?.getResult
        network = MethodAwareMockNetworkClient()
        let configService = ConfigService(networkClient: network, storage: storage)
        let consentService = ConsentService(
            networkClient: network,
            storage: storage,
            privacyDomain: privacyDomain
        )
        sut = ConsentManager(
            storage: storage,
            configService: configService,
            consentService: consentService
        )
        let config = UCFixtures.makeConfig(privacyDomain: privacyDomain, syncOptout: true)
        guard let data = try? JSONEncoder().encode(config),
              let url = URL(string: "https://\(privacyDomain)/config.json")
        else {
            XCTFail("Failed to encode UC config fixture")
            return
        }
        network.getResult = .success(data)
        let expectation = expectation(description: "config loaded")
        sut.loadConfig(from: url) { result in
            if case let .failure(error) = result {
                XCTFail("Config load failed: \(error)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        network.methods = []
        if let servedRecord {
            network.getResult = servedRecord
        }
    }

    private func sync(
        _ identifier: String,
        trackingSignal: TrackingSignal = .authorized
    ) -> Result<Void, ConsentError> {
        let expectation = expectation(description: "sync \(identifier)")
        var outcome: Result<Void, ConsentError> = .failure(.notInitialized)
        sut.syncUserIdentifier(identifier, apiKey: testApiKey, trackingSignal: trackingSignal) { result in
            outcome = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        return outcome
    }

    private func save(_ preferences: ConsentPreferences) throws {
        let expectation = expectation(description: "savePreferences")
        var outcome: Result<Void, ConsentError> = .failure(.notInitialized)
        sut.savePreferences(preferences) { result in
            outcome = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        try outcome.get()
    }

    private func setCcpaOptout(_ optedOut: Bool) -> Result<Void, ConsentError> {
        let expectation = expectation(description: "setCcpaOptout")
        var outcome: Result<Void, ConsentError> = .failure(.notInitialized)
        sut.setCcpaOptout(optedOut) { result in
            outcome = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        return outcome
    }

    private func storedMarketing() -> Bool? {
        storage.loadPreferences()?.cookieOptions.first { $0.gtmKey == "dg-category-marketing" }?.isEnabled
    }

    private func writtenCookieOptions() -> [String: Bool]? {
        guard let body = network.lastPostBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return nil }
        return (json["consent_preferences"] as? [String: Any])?["cookieOptions"] as? [String: Bool]
    }

    private func hash(_ identifier: String) throws -> String {
        try ConsentService.validatedUserHash(identifier: identifier, config: XCTUnwrap(sut.config))
    }

    private func choice(marketing: Bool, analytics: Bool) -> ConsentPreferences {
        ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "dg-category-essential", isEnabled: true),
                CategoryConsent(gtmKey: "dg-category-marketing", isEnabled: marketing),
                CategoryConsent(gtmKey: "dg-category-analytics", isEnabled: analytics),
            ]
        )
    }

    private func foundRecordJSON(marketing: Bool, analytics: Bool? = nil) -> Data {
        let analyticsEntry = analytics.map { #", "dg-category-analytics": \#($0)"# } ?? ""
        return Data("""
        {
          "status": "found",
          "consent_preferences": {
            "isCustomised": true,
            "cookieOptions": {
              "dg-category-essential": true,
              "dg-category-marketing": \(marketing)\(analyticsEntry)
            }
          },
          "consent_mode": "optin",
          "platform": "web",
          "gpc": false,
          "ccpa_optout": false
        }
        """.utf8)
    }
}
