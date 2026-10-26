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
        XCTAssertEqual(writtenCookieOptions(), [:], "CCPA-only: the record's raw opt-in is untouched")
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

    private func foundRecordJSON(marketing: Bool, analytics: Bool? = nil, gpc: Bool = false) -> Data {
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
          "gpc": \(gpc),
          "ccpa_optout": false,
          "updated_at": "\(UCFixtures.pastUpdatedAt)"
        }
        """.utf8)
    }
}

// MARK: - Standalone rehydrate, saves during the read, setter calls during a first login

// In an extension so the primary test class stays within SwiftLint's type_body_length limit.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension UniversalConsentResyncTests {
    func testStandaloneRehydrateUnderATTIsNotWrittenByTheNextResync() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA).get())

        XCTAssertEqual(try rehydrate(userA, trackingSignal: .denied).get(), true)
        XCTAssertEqual(storedMarketing(), false, "local state holds the ATT-suppressed view")
        XCTAssertNoThrow(try sync(userA, trackingSignal: .denied).get())

        XCTAssertEqual(network.methods, [.get, .get, .get], "the suppressed map is never written")
        XCTAssertNil(network.lastPostBody)

        XCTAssertNoThrow(try setCcpaOptout(true).get())
        XCTAssertEqual(network.methods.last, .post)
        XCTAssertEqual(writtenCookieOptions(), [:], "CCPA-only: the record's raw opt-in is untouched")
    }

    func testStandaloneRehydrateOfAGPCRecordIsNotWrittenByTheNextResyncAfterARelaunch() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA).get())

        // Another device recorded GPC since; the raw opt-in is unchanged.
        network.getResult = .success(foundRecordJSON(marketing: true, gpc: true))
        XCTAssertEqual(try rehydrate(userA).get(), true)
        XCTAssertEqual(storedMarketing(), false, "local state holds the GPC-suppressed view")
        let state = try XCTUnwrap(storage.loadSyncState())
        XCTAssertEqual(state.syncedLocal, storage.loadPreferences(), "what the rehydrate stored")
        XCTAssertEqual(state.syncedRaw?.cookieOptions.first { $0.gtmKey == "dg-category-marketing" }?.isEnabled, true)

        relaunch()
        XCTAssertNoThrow(try sync(userA).get())
        XCTAssertEqual(network.methods, [.get], "no POST of the suppressed map")
        XCTAssertNil(network.lastPostBody)
    }

    func testStandaloneRehydrateForAnotherIdentityClearsTheSyncState() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA).get())

        XCTAssertEqual(try rehydrate(userB).get(), true)

        XCTAssertNil(storage.loadSyncState(), "the stored view is no longer what user A's sync left")
        XCTAssertEqual(storage.loadBoundUserHash(), try hash(userA))
    }

    func testLogoutDuringAStandaloneRehydratePersistsNothing() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        network.deferGet = true
        var outcome: Result<Bool, ConsentError>?
        sut.rehydrateFromUniversalConsent(userA, apiKey: testApiKey, trackingSignal: .authorized) { outcome = $0 }

        sut.clearUserIdentifier()
        try XCTUnwrap(network.pendingGetCompletion)(network.getResult)

        XCTAssertThrowsError(try XCTUnwrap(outcome).get())
        XCTAssertNil(storage.loadPreferences(), "the logout's neutral state stands")
        XCTAssertNil(storage.loadSyncState())
    }

    func testSaveDuringAResyncReadIsWrittenByTheNextResync() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA).get())

        // The record is gone (a miss), and the user saves a new choice while the read is in flight.
        network.getResult = .success(notFound)
        network.deferGet = true
        var outcome: Result<Void, ConsentError>?
        sut.syncUserIdentifier(userA, apiKey: testApiKey, trackingSignal: .authorized) { outcome = $0 }
        try save(choice(marketing: false, analytics: true))
        network.deferGet = false
        try XCTUnwrap(network.pendingGetCompletion)(network.getResult)
        XCTAssertNoThrow(try XCTUnwrap(outcome).get())

        network.methods = []
        network.lastPostBody = nil
        XCTAssertNoThrow(try sync(userA).get())

        XCTAssertEqual(network.methods, [.get, .post], "the mid-read save is a change")
        XCTAssertEqual(writtenCookieOptions()?["dg-category-marketing"], false)
    }

    func testSaveTheResyncsAdoptOverwroteIsNotLaterWrittenAsTheSuppressedView() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA, trackingSignal: .denied).get())

        network.deferGet = true
        var outcome: Result<Void, ConsentError>?
        sut.syncUserIdentifier(userA, apiKey: testApiKey, trackingSignal: .denied) { outcome = $0 }
        try save(choice(marketing: true, analytics: false))
        network.deferGet = false
        // The adopt lands after the save and overwrites it with the record's suppressed view.
        try XCTUnwrap(network.pendingGetCompletion)(network.getResult)
        XCTAssertNoThrow(try XCTUnwrap(outcome).get())
        XCTAssertEqual(storedMarketing(), false)

        network.methods = []
        network.lastPostBody = nil
        XCTAssertNoThrow(try sync(userA, trackingSignal: .denied).get())

        XCTAssertEqual(network.methods, [.get], "the suppressed view is not a user change")
        XCTAssertNil(network.lastPostBody)
    }

    func testSetterDuringAFirstLoginReadIsNotRevertedByTheNextResync() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        network.deferGet = true
        var outcome: Result<Void, ConsentError>?
        sut.syncUserIdentifier(userA, apiKey: testApiKey, trackingSignal: .authorized) { outcome = $0 }
        XCTAssertNoThrow(try setCcpaOptout(true).get())
        network.deferGet = false
        try XCTUnwrap(network.pendingGetCompletion)(network.getResult)
        XCTAssertNoThrow(try XCTUnwrap(outcome).get())
        XCTAssertTrue(sut.getCcpaOptout())
        XCTAssertTrue(storage.loadCcpaWritePending(), "no write carried it, so it is pending")

        XCTAssertNoThrow(try rehydrate(userA).get())
        XCTAssertTrue(sut.getCcpaOptout(), "the record's older false does not replace it")
        XCTAssertNil(network.lastPostBody, "a standalone rehydrate never writes")

        // The next re-sync carries it, although the categories are unchanged.
        XCTAssertNoThrow(try sync(userA).get())
        XCTAssertEqual(writtenCcpaOptout(), true)
        XCTAssertFalse(storage.loadCcpaWritePending())
        XCTAssertTrue(sut.getCcpaOptout())
    }

    func testSetterWithNoSessionAfterARelaunchIsNotRevertedByTheResync() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA).get())

        relaunch()
        XCTAssertNoThrow(try setCcpaOptout(true).get())
        XCTAssertEqual(network.methods, [], "no session in this process, so it stays local")
        XCTAssertNoThrow(try sync(userA).get())

        XCTAssertTrue(sut.getCcpaOptout(), "the record's older false does not replace it")
    }

    /// TRUST-3308 (web: consent-banner 7195aa3): a setter write-through that fails leaves the choice
    /// pending, so the next re-sync does not replace it with the record's stale value and, with a
    /// session again (TRUST-2902), flushes it; logout clears it.
    func testSetterWhoseWriteFailedIsNotRevertedByTheResync() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA).get())

        network.postResult = .failure(.networkError("offline"))
        XCTAssertThrowsError(try setCcpaOptout(true).get())
        XCTAssertTrue(storage.loadCcpaWritePending(), "the failed write did not carry it")

        network.postResult = .success(Data(#"{"status":"ok"}"#.utf8))
        XCTAssertNoThrow(try sync(userA).get())
        XCTAssertTrue(sut.getCcpaOptout(), "the record's older false does not replace it")
        XCTAssertEqual(writtenCcpaOptout(), true, "the re-sync flushes the pending choice")
        XCTAssertFalse(storage.loadCcpaWritePending())

        network.postResult = .failure(.networkError("offline"))
        XCTAssertThrowsError(try setCcpaOptout(false).get())
        XCTAssertTrue(storage.loadCcpaWritePending())
        sut.clearUserIdentifier()
        XCTAssertFalse(storage.loadCcpaWritePending())
        XCTAssertFalse(sut.getCcpaOptout())
    }

    private func rehydrate(
        _ identifier: String,
        trackingSignal: TrackingSignal = .authorized
    ) -> Result<Bool, ConsentError> {
        let expectation = expectation(description: "rehydrate \(identifier)")
        var outcome: Result<Bool, ConsentError> = .failure(.notInitialized)
        sut.rehydrateFromUniversalConsent(identifier, apiKey: testApiKey, trackingSignal: trackingSignal) { result in
            outcome = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        return outcome
    }

    private func writtenCcpaOptout() -> Bool? {
        guard let body = network.lastPostBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return nil }
        return json["ccpa_optout"] as? Bool
    }
}

// MARK: - A pending CCPA choice is flushed by the next re-sync

// A setter call made while bound but with no session (after a relaunch, before the host re-syncs)
// is marked pending and stays local. The next re-sync is when a session exists again, so it writes
// the pending flag with the record's own raw choice, even though the categories are unchanged.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension UniversalConsentResyncTests {
    func testSetterWithNoSessionAfterARelaunchIsWrittenByTheNextResync() throws {
        network.getResult = .success(foundRecordJSON(marketing: true, analytics: false))
        XCTAssertNoThrow(try sync(userA).get())

        relaunch()
        XCTAssertNoThrow(try setCcpaOptout(true).get())
        XCTAssertEqual(network.methods, [], "no session in this process, so it stays local")
        XCTAssertTrue(storage.loadCcpaWritePending())
        // The setter ran well before the re-sync that finally sends it.
        let setterTs: Int64 = 1_700_000_000
        storage.saveCcpaChoice(true, now: setterTs)

        XCTAssertNoThrow(try sync(userA).get())

        XCTAssertEqual(network.methods, [.get, .post], "the pending choice is flushed")
        XCTAssertEqual(writtenCcpaOptout(), true)
        XCTAssertEqual(writtenCookieOptions(), [:], "CCPA-only, so no category changes at any stamp")
        let body = try XCTUnwrap(network.lastPostBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        })
        // Stamped with when the setter was called: not the record's time (it would tie the record's
        // `ccpa_optout` register, and a tie keeps an opt-out), nor the send time (a late flush
        // would out-rank a newer CCPA choice made elsewhere meanwhile).
        XCTAssertEqual((body["decision_ts"] as? NSNumber)?.int64Value, setterTs)
        XCTAssertFalse(storage.loadCcpaWritePending(), "the write carried it")
        XCTAssertTrue(sut.getCcpaOptout())

        // Flushed and unchanged since: the next re-sync writes nothing.
        network.methods = []
        XCTAssertNoThrow(try sync(userA).get())
        XCTAssertEqual(network.methods, [.get])
    }

    func testPendingFlushSendsTheRecordsRawOptInNotTheATTSuppressedView() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA, trackingSignal: .denied).get())

        relaunch()
        XCTAssertNoThrow(try setCcpaOptout(true).get())
        XCTAssertNoThrow(try sync(userA, trackingSignal: .denied).get())

        XCTAssertEqual(network.methods, [.get, .post])
        XCTAssertEqual(writtenCookieOptions(), [:], "CCPA-only: the record's raw opt-in is untouched")
        XCTAssertEqual(storedMarketing(), false, "local keeps the suppressed view")
    }

    func testFailedPendingFlushStaysPendingAndIsRetriedByTheNextResync() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA).get())

        relaunch()
        XCTAssertNoThrow(try setCcpaOptout(true).get())
        network.postResult = .failure(.networkError("offline"))
        XCTAssertThrowsError(try sync(userA).get())
        XCTAssertTrue(storage.loadCcpaWritePending(), "nothing reached the record")
        XCTAssertTrue(sut.getCcpaOptout(), "the record's older false does not replace it")

        network.postResult = .success(Data(#"{"status":"ok"}"#.utf8))
        network.lastPostBody = nil
        XCTAssertNoThrow(try sync(userA).get())
        XCTAssertEqual(writtenCcpaOptout(), true)
        XCTAssertFalse(storage.loadCcpaWritePending())
    }

    /// A failed flush still records the adopt it made as the sync state: an ATT transition to denied
    /// suppressed marketing locally, and the retry must not read that as the user turning it off.
    func testFailedFlushAfterAnATTDenialDoesNotWriteTheSuppressedViewOnTheRetry() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA, trackingSignal: .authorized).get())

        relaunch()
        XCTAssertNoThrow(try setCcpaOptout(true).get())
        network.postResult = .failure(.networkError("offline"))
        XCTAssertThrowsError(try sync(userA, trackingSignal: .denied).get())
        XCTAssertEqual(storedMarketing(), false, "local holds the suppressed view")

        network.postResult = .success(Data(#"{"status":"ok"}"#.utf8))
        network.lastPostBody = nil
        XCTAssertNoThrow(try sync(userA, trackingSignal: .denied).get())
        XCTAssertEqual(writtenCcpaOptout(), true, "the retry flushes the pending choice")
        XCTAssertEqual(writtenCookieOptions(), [:], "CCPA-only, never the suppressed view")
        XCTAssertFalse(storage.loadCcpaWritePending())
    }

    func testPendingChoiceIsNotFlushedOverAMiss() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))
        XCTAssertNoThrow(try sync(userA).get())

        relaunch()
        XCTAssertNoThrow(try setCcpaOptout(true).get())
        network.getResult = .success(notFound)
        XCTAssertNoThrow(try sync(userA).get())

        XCTAssertEqual(network.methods, [.get], "no raw choice to re-send, and defaults are never seeded")
        XCTAssertTrue(storage.loadCcpaWritePending(), "still waiting for a write to carry it")
    }
}
