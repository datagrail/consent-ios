import CryptoKit
@testable import DataGrailConsent
import XCTest

/// TRUST-3223 (iOS port of consent-banner TRUST-3154): a stale device's re-sync must not undo a
/// newer choice made on another device. Every write carries the time the choice was made
/// (`is_explicit` + `decision_ts`, signed into provDigest), and a re-sync writes a local change
/// over a found record only when it is strictly newer than the record's `updated_at`.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class UniversalConsentDecisionTsTests: XCTestCase {
    private var storage: ConsentStorage!
    private var network: MethodAwareMockNetworkClient!
    private var sut: ConsentManager!
    private var signedPayloads: [UniversalConsentSigningPayload] = []
    /// Run (once) by the manager's injected seam after a sync's read persisted its outcome.
    private var onReadPersisted: (() -> Void)?
    private let testApiKey = "dg_live_test_key_123"
    private let privacyDomain = "consent.test.com"
    private let userA = "uc-opaque-id-7f3a9c"

    override func setUp() {
        super.setUp()
        storage = ConsentStorage()
        storage.clearAll()
        signedPayloads = []
        onReadPersisted = nil
        network = MethodAwareMockNetworkClient()
        sut = ConsentManager(
            storage: storage,
            configService: ConfigService(networkClient: network, storage: storage),
            consentService: ConsentService(networkClient: network, storage: storage, privacyDomain: privacyDomain),
            afterSyncReadPersisted: { [weak self] in
                let hook = self?.onReadPersisted
                self?.onReadPersisted = nil
                hook?()
            }
        )
        loadConfig()
    }

    override func tearDown() {
        storage.clearAll()
        sut = nil
        network = nil
        storage = nil
        super.tearDown()
    }

    // MARK: - The P0-06 shape

    /// iOS equivalent of sign-off P0-06: the user chose on this device while signed in, then revoked
    /// on another device; this device's re-sync must adopt the revocation, not write the old grant.
    func testStaleLocalChoiceAdoptsANewerRevocationInsteadOfUndoingIt() throws {
        try bindAfterFirstSync()
        try save(marketing: true)
        let localTs = try XCTUnwrap(storage.loadDecisionTs())

        // Another device revoked marketing AFTER this device's choice.
        let revokedAt = localTs + 5
        network.getResult = .success(foundRecordJSON(marketing: false, updatedAt: revokedAt))
        XCTAssertNoThrow(try sync().get())

        XCTAssertEqual(network.methods, [.get], "the stale grant is not written")
        XCTAssertEqual(storedMarketing(), false, "the newer revocation is adopted")
        XCTAssertEqual(storage.loadDecisionTs(), revokedAt, "local takes the record's decision time")
    }

    func testLocalChoiceNewerThanTheRecordIsWrittenWithItsDecisionTime() throws {
        try bindAfterFirstSync()
        try save(marketing: false)
        let localTs = try XCTUnwrap(storage.loadDecisionTs())

        network.getResult = .success(foundRecordJSON(marketing: true, updatedAt: localTs - 60))
        XCTAssertNoThrow(try sync().get())

        XCTAssertEqual(network.methods, [.get, .post])
        let body = try XCTUnwrap(writtenBody())
        XCTAssertEqual((body["consent_preferences"] as? [String: Any])?["cookieOptions"] as? [String: Bool], [
            "dg-category-essential": true,
            "dg-category-marketing": false,
        ])
        XCTAssertEqual(body["is_explicit"] as? Bool, true)
        XCTAssertEqual((body["decision_ts"] as? NSNumber)?.int64Value, localTs, "when the user chose, not now")
        XCTAssertEqual(storedMarketing(), false, "this device keeps the newer choice it wrote, not the older record")
        XCTAssertEqual(storage.loadDecisionTs(), localTs)
        XCTAssertEqual(
            try XCTUnwrap(signedPayloads.last).stringToSign.split(separator: ":").last.map(String.init),
            sha256Hex("true\n\(localTs)\n"),
            "provDigest binds the body's decision_ts"
        )
    }

    /// TRUST-2902: a re-sync over a pending CCPA choice keeps the flag and the setter's time, so a
    /// later CCPA-only flush is not stamped now.
    func testWriteThroughKeepsTheSettersCcpaTime() throws {
        try bindAfterFirstSync()
        try save(marketing: false)
        let localTs = try XCTUnwrap(storage.loadDecisionTs())
        storage.saveCcpaChoice(true, now: 1_650_000_000)
        storage.saveCcpaWritePending(true)

        network.getResult = .success(foundRecordJSON(marketing: true, updatedAt: localTs - 60))
        network.postResult = .failure(.networkError("offline"))
        XCTAssertThrowsError(try sync().get())

        XCTAssertTrue(storage.loadCcpaOptout())
        XCTAssertEqual(storage.loadCcpaDecisionTs(), 1_650_000_000)
    }

    func testSameSecondTieAdoptsTheRecord() throws {
        try bindAfterFirstSync()
        try save(marketing: true)
        let localTs = try XCTUnwrap(storage.loadDecisionTs())

        network.getResult = .success(foundRecordJSON(marketing: false, updatedAt: localTs))
        XCTAssertNoThrow(try sync().get())

        XCTAssertEqual(network.methods, [.get], "newer means strictly newer")
        XCTAssertEqual(storedMarketing(), false)
    }

    func testChoiceWithNoRecordedTimeAdoptsAFoundRecord() throws {
        try bindAfterFirstSync()
        try save(marketing: true)
        storage.clearDecisionTs() // a choice stored before the SDK recorded decision times

        network.getResult = .success(foundRecordJSON(marketing: false, updatedAt: 1_600_000_000))
        XCTAssertNoThrow(try sync().get())

        XCTAssertEqual(network.methods, [.get], "an unknown time cannot prove it is newer")
        XCTAssertEqual(storedMarketing(), false)
    }

    func testRecordWithNoUpdatedAtIsAdopted() throws {
        try bindAfterFirstSync()
        try save(marketing: true)

        network.getResult = .success(foundRecordJSON(marketing: false, updatedAt: nil))
        XCTAssertNoThrow(try sync().get())

        XCTAssertEqual(network.methods, [.get])
        XCTAssertEqual(storedMarketing(), false)
        XCTAssertNil(storage.loadDecisionTs(), "the adopted choice's time is unknown")
    }

    func testSignalOnlyRecordStillTakesALocalChoiceWithItsDecisionTime() throws {
        try bindAfterFirstSync()
        try save(marketing: true)
        let localTs = try XCTUnwrap(storage.loadDecisionTs())

        // A record holding only a signal has no category decision this choice could undo.
        network.getResult = .success(Data(#"{"status":"found","gpc":true,"updated_at":"2099-01-01T00:00:00Z"}"#.utf8))
        XCTAssertNoThrow(try sync().get())

        XCTAssertEqual(network.methods, [.get, .post])
        XCTAssertEqual((writtenBody()?["decision_ts"] as? NSNumber)?.int64Value, localTs)
    }

    /// TRUST-3311 (consent-react #47): a setCcpaOptout write-through that carries a local change made
    /// since the sync stamps it with the stored choice's decision time, so it cannot out-rank a newer
    /// revocation elsewhere. (Unchanged since the sync, it sends no category at all: TRUST-2902.)
    func testSetterWriteThroughIsCcpaOnlyDatedWhenTheCcpaChoiceWasMade() throws {
        try bindAfterFirstSync()
        try save(marketing: true)
        storage.saveDecisionTs(1_600_000_100)
        network.postBodies = []

        let expectation = expectation(description: "setCcpaOptout")
        sut.setCcpaOptout(true) { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        // The unsynced change first at its own time (as consent-banner #756), then the CCPA-only
        // write (TRUST-2591 decision, 2026-10-26): the flag and its provenance only.
        XCTAssertEqual(network.methods, [.post, .post])
        let first = try XCTUnwrap(network.postBodies.first.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        })
        XCTAssertEqual((first["decision_ts"] as? NSNumber)?.int64Value, 1_600_000_100, "the change's own time")
        let body = try XCTUnwrap(writtenBody())
        XCTAssertEqual(Set(body.keys), ["customer_id", "user_hash", "consent_preferences", "ccpa_optout",
                                        "is_explicit", "decision_ts"])
        XCTAssertEqual(body["consent_preferences"] as? [String: [String: Bool]], ["cookieOptions": [:]])
        XCTAssertEqual(body["ccpa_optout"] as? Bool, true)
        XCTAssertEqual((body["decision_ts"] as? NSNumber)?.int64Value, storage.loadCcpaDecisionTs(), "the CCPA time")
    }

    /// TRUST-2902 (lucasv-dg, consent-android #74): a local change stored before decision times were
    /// recorded does not ride a setter write stamped "now", which could undo a newer revocation.
    func testSetterAfterALocalChangeWithNoRecordedTimeIsCcpaOnly() throws {
        try bindAfterFirstSync()
        try storage.savePreferences(choice(marketing: false))
        storage.clearDecisionTs()
        storage.clearSyncState()

        let expectation = expectation(description: "setCcpaOptout")
        sut.setCcpaOptout(true) { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        let prefs = try XCTUnwrap(writtenBody()?["consent_preferences"] as? [String: Any])
        XCTAssertEqual(prefs["cookieOptions"] as? [String: Bool], [:])
        XCTAssertEqual((writtenBody()?["decision_ts"] as? NSNumber)?.int64Value, storage.loadCcpaDecisionTs())
    }

    // MARK: - Unknown decision time is byte-identical to before

    func testMissWithNoRecordedTimeSendsNoProvenanceAndSignsTheRequestTimestamp() throws {
        try storage.savePreferences(choice(marketing: true))
        network.getResult = .success(notFound)

        XCTAssertNoThrow(try sync().get())

        XCTAssertEqual(network.methods, [.get, .post])
        let body = try XCTUnwrap(writtenBody())
        XCTAssertNil(body["is_explicit"])
        XCTAssertNil(body["decision_ts"])
        let payload = try XCTUnwrap(signedPayloads.last)
        XCTAssertEqual(
            payload.stringToSign.split(separator: ":").last.map(String.init),
            sha256Hex("true\n\(payload.timestamp)\n"),
            "the edge's resolved-default triple, as before TRUST-3223"
        )
    }

    // MARK: - What sets and clears the stored decision time

    func testAdoptTakesTheRecordsTimeAndLogoutClearsIt() throws {
        network.getResult = .success(foundRecordJSON(marketing: true, updatedAt: 1_700_000_000))
        XCTAssertNoThrow(try sync().get())
        XCTAssertEqual(storage.loadDecisionTs(), 1_700_000_000, "an adopt is not a choice made now")

        sut.clearUserIdentifier()
        XCTAssertNil(storage.loadDecisionTs())
    }

    func testAChoiceRightAfterAdoptingARecordAheadOfThisClockStillOrdersAfterIt() throws {
        let now = ConsentStorage.nowSeconds()
        storage.saveDecisionTs(now + 200) // adopted from a record stamped ahead of this clock
        storage.saveDecisionTs(now: now)
        XCTAssertEqual(storage.loadDecisionTs(now: now), now + 201, "monotonic, never earlier than the last")
    }

    func testAStampFarAheadOfThisClockReadsAsUnknown() {
        let now = ConsentStorage.nowSeconds()
        storage.saveDecisionTs(now + ConsentStorage.decisionTsStoredToleranceSeconds + 1)
        XCTAssertNil(storage.loadDecisionTs(now: now))

        storage.saveDecisionTs(now: now)
        XCTAssertEqual(storage.loadDecisionTs(now: now), now, "a bogus stamp does not drag the next one ahead")
    }

    func testRemovingTheStoredChoiceClearsItsTime() throws {
        try storage.savePreferences(choice(marketing: true))
        storage.saveDecisionTs()
        storage.removePreferences()
        XCTAssertNil(storage.loadDecisionTs())
    }

    // MARK: - Helpers

    private let notFound = Data(#"{"status":"not_found"}"#.utf8)

    private func loadConfig() {
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
    }

    /// Bind the device to `userA` by adopting a record from well before any test's choice.
    private func bindAfterFirstSync() throws {
        network.getResult = .success(foundRecordJSON(marketing: true, updatedAt: 1_600_000_000))
        try sync().get()
        network.methods = []
        signedPayloads = []
    }

    private func sync() -> Result<Void, ConsentError> {
        let expectation = expectation(description: "sync")
        var outcome: Result<Void, ConsentError> = .failure(.notInitialized)
        sut.syncUserIdentifier(
            userA,
            apiKey: testApiKey,
            trackingSignal: .authorized,
            getSignature: { [weak self] payload, done in
                self?.signedPayloads.append(payload)
                done(.success(UniversalConsentSignature(signature: "sig", keyId: "k1")))
            },
            completion: { result in
                outcome = result
                expectation.fulfill()
            }
        )
        wait(for: [expectation], timeout: 1.0)
        return outcome
    }

    private func save(marketing: Bool) throws {
        let expectation = expectation(description: "savePreferences")
        var outcome: Result<Void, ConsentError> = .failure(.notInitialized)
        sut.savePreferences(choice(marketing: marketing)) { result in
            outcome = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        try outcome.get()
        network.methods = []
    }

    private func choice(marketing: Bool) -> ConsentPreferences {
        ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "dg-category-essential", isEnabled: true),
                CategoryConsent(gtmKey: "dg-category-marketing", isEnabled: marketing),
            ]
        )
    }

    private func storedMarketing() -> Bool? {
        storage.loadPreferences()?.cookieOptions.first { $0.gtmKey == "dg-category-marketing" }?.isEnabled
    }

    private func writtenBody() -> [String: Any]? {
        guard let body = network.lastPostBody else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }

    private func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func foundRecordJSON(marketing: Bool, updatedAt: Int64?, ccpaOptout: Bool = false) -> Data {
        let updatedAtEntry = updatedAt.map { seconds -> String in
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return #", "updated_at": "\#(iso.string(from: Date(timeIntervalSince1970: TimeInterval(seconds))))""#
        } ?? ""
        return Data("""
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
          "gpc": false,
          "ccpa_optout": \(ccpaOptout)\(updatedAtEntry)
        }
        """.utf8)
    }
}

// MARK: - A save during a keep-local re-sync

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension UniversalConsentDecisionTsTests {
    /// A re-sync that keeps the newer local choice decides so before storing the record, so it never
    /// writes the record and then puts the pre-read choice back: a save landing mid-sync survives.
    func testASaveDuringAKeepLocalReSyncIsNotUndoneByIt() throws {
        try bindAfterFirstSync()
        try save(marketing: false)
        let localTs = try XCTUnwrap(storage.loadDecisionTs())
        let recordTs = localTs - 60

        let outcome = try resyncSavingDuringTheRead(foundRecordJSON(marketing: false, updatedAt: recordTs))

        XCTAssertNoThrow(try outcome.get())
        XCTAssertEqual(storedMarketing(), true, "the mid-sync save is kept, not the pre-read choice")
        XCTAssertNotEqual(storage.loadDecisionTs(), recordTs, "the record was not adopted either")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(storage.loadDecisionTs()), localTs)
        XCTAssertNotNil(storage.loadSyncState(), "the written save counts as synced")
        // The write carries the mid-sync save with its own time, not the pre-read choice.
        let body = try XCTUnwrap(writtenBody())
        let prefs = try XCTUnwrap(body["consent_preferences"] as? [String: Any])
        let written = try XCTUnwrap(prefs["cookieOptions"] as? [String: Bool])
        XCTAssertEqual(written["dg-category-marketing"], true)
        XCTAssertEqual((body["decision_ts"] as? NSNumber)?.int64Value, storage.loadDecisionTs())
    }

    /// A save made during the read is newer than anything the read saw. A record written by a device
    /// whose clock is ahead must not out-rank it at the edge, while this sync records it as synced.
    func testASaveDuringTheReadIsStampedAfterARecordFromAClockAhead() throws {
        try bindAfterFirstSync()
        try save(marketing: false)
        let recordTs = try XCTUnwrap(storage.loadDecisionTs()) + 100

        let outcome = try resyncSavingDuringTheRead(foundRecordJSON(marketing: false, updatedAt: recordTs))

        XCTAssertNoThrow(try outcome.get())
        XCTAssertEqual(storedMarketing(), true)
        XCTAssertEqual(storage.loadDecisionTs(), recordTs + 1, "stored so, as a CCPA adopt floors the next toggle")
        let body = try XCTUnwrap(writtenBody())
        XCTAssertEqual((body["decision_ts"] as? NSNumber)?.int64Value, recordTs + 1)
    }

    /// A save during the read that equals the record's raw choice sends nothing, so its decision
    /// time is not moved past the record's: no write carries it there.
    func testASaveDuringTheReadEqualToTheRecordKeepsItsOwnTime() throws {
        try bindAfterFirstSync()
        try save(marketing: false)
        let recordTs = try XCTUnwrap(storage.loadDecisionTs()) + 100

        let outcome = try resyncSavingDuringTheRead(foundRecordJSON(marketing: true, updatedAt: recordTs))

        XCTAssertNoThrow(try outcome.get())
        XCTAssertEqual(network.methods, [], "nothing to send: the record already holds the save")
        XCTAssertEqual(storedMarketing(), true)
        XCTAssertLessThan(try XCTUnwrap(storage.loadDecisionTs()), recordTs, "the save keeps its own time")
    }

    /// A mid-read save over a record 300-599 s ahead of this clock (this clock is behind the edge's,
    /// which clamps to its own now + 300 s) is stamped one second after the record, never capped at
    /// the edge's clamp: a capped stamp would be older than the record, and the next re-sync would
    /// adopt the record over the save. The stamp is still within the stored tolerance, so it reads
    /// back. It is not recorded as synced; the next re-sync finds it on the record and keeps it.
    func testAMidReadSaveOverARecordFarAheadIsStampedAfterItUncapped() throws {
        try bindAfterFirstSync()
        try save(marketing: false)
        let recordTs = ConsentStorage.nowSeconds() + 400

        let outcome = try resyncSavingDuringTheRead(foundRecordJSON(marketing: false, updatedAt: recordTs))

        XCTAssertNoThrow(try outcome.get())
        XCTAssertEqual(storedMarketing(), true)
        let body = try XCTUnwrap(writtenBody())
        XCTAssertEqual((body["decision_ts"] as? NSNumber)?.int64Value, recordTs + 1, "after the record, not capped")
        XCTAssertEqual(storage.loadDecisionTs(), recordTs + 1, "past the edge's clamp, still readable")
        XCTAssertNil(storage.loadSyncState(), "a stamp one past the record may tie it at the edge's clamp")

        // The edge stored the save (its clock is past the record's clamp second): the next re-sync
        // finds it on the record and keeps it.
        network.methods = []
        network.getResult = .success(foundRecordJSON(marketing: true, updatedAt: recordTs + 1))
        XCTAssertNoThrow(try sync().get())
        XCTAssertEqual(network.methods, [.get])
        XCTAssertEqual(storedMarketing(), true, "the save is not reverted")
    }

    /// A mid-read save over a record at the edge's future clamp ties it there (the edge restamps one
    /// past the clamp to the clamp, and a tie keeps the record). The save is not recorded as synced,
    /// so the next re-sync against the unchanged record sees the save as newer and writes it again.
    func testAMidReadSaveThatTiesARecordAtTheClampIsWrittenAgainOnTheNextReSync() throws {
        try bindAfterFirstSync()
        try save(marketing: false)
        let recordTs = ConsentStorage.nowSeconds() + ConsentStorage.decisionTsFutureToleranceSeconds

        let outcome = try resyncSavingDuringTheRead(foundRecordJSON(marketing: false, updatedAt: recordTs))

        XCTAssertNoThrow(try outcome.get())
        XCTAssertEqual(storage.loadDecisionTs(), recordTs + 1, "stored so it still reads back")
        XCTAssertNil(storage.loadSyncState())

        // The edge kept the record on the tie: the record read back is unchanged.
        network.methods = []
        network.postBodies = []
        network.getResult = .success(foundRecordJSON(marketing: false, updatedAt: recordTs))
        XCTAssertNoThrow(try sync().get())

        XCTAssertEqual(network.methods, [.get, .post], "the save is written again, not adopted over")
        let body = try XCTUnwrap(writtenBody())
        let prefs = try XCTUnwrap(body["consent_preferences"] as? [String: Any])
        XCTAssertEqual((prefs["cookieOptions"] as? [String: Bool])?["dg-category-marketing"], true)
        XCTAssertEqual((body["decision_ts"] as? NSNumber)?.int64Value, recordTs + 1)
        XCTAssertEqual(storedMarketing(), true)
    }

    /// A tied save written again by the next re-sync is still one second past the unchanged record,
    /// so that retry may tie it too. With this clock 10 s ahead of the edge's (the record sits at the
    /// edge's clamp, 290 s past this clock), the stamp passes this device's own clamp check, so a
    /// retry that forgot the uncertainty would be recorded as synced and the following re-sync would
    /// adopt the record over the save. It stays unsynced until a read finds the save on the record.
    func testATiedSaveRetriedUnderAClockAheadOfTheEdgeIsNotRecordedAsSynced() throws {
        try bindAfterFirstSync()
        try save(marketing: false)
        let recordTs = ConsentStorage.nowSeconds() + ConsentStorage.decisionTsFutureToleranceSeconds - 10

        XCTAssertNoThrow(try resyncSavingDuringTheRead(foundRecordJSON(marketing: false, updatedAt: recordTs)).get())
        XCTAssertEqual(storage.loadDecisionTs(), recordTs + 1)
        XCTAssertTrue(ConsentManager.edgeStoresAsSent(recordTs + 1), "this clock alone would call it stored")
        XCTAssertNil(storage.loadSyncState())

        // Second POST: the record is unchanged (the edge kept it on the tie), so the save is written
        // again, and in the same edge second it ties again.
        network.methods = []
        network.postBodies = []
        network.getResult = .success(foundRecordJSON(marketing: false, updatedAt: recordTs))
        XCTAssertNoThrow(try sync().get())
        XCTAssertEqual(network.methods, [.get, .post])
        XCTAssertEqual((try XCTUnwrap(writtenBody())["decision_ts"] as? NSNumber)?.int64Value, recordTs + 1)
        XCTAssertNil(storage.loadSyncState(), "the retry may have tied too: not recorded as synced")

        // Third read: still unchanged, so the save is written again rather than adopted over.
        network.methods = []
        network.postBodies = []
        XCTAssertNoThrow(try sync().get())
        XCTAssertEqual(network.methods, [.get, .post], "the save is written again, not adopted over")
        XCTAssertEqual(storedMarketing(), true)

        // Once a read finds the save on the record, it is adopted and recorded as synced.
        network.methods = []
        network.getResult = .success(foundRecordJSON(marketing: true, updatedAt: recordTs + 1))
        XCTAssertNoThrow(try sync().get())
        XCTAssertEqual(network.methods, [.get])
        XCTAssertEqual(storedMarketing(), true)
        XCTAssertNotNil(storage.loadSyncState(), "a read that found the save settles it")
    }

    /// A save that lands after an adopting re-sync persisted the record, before the sync applies
    /// that outcome, replaced the adopted choice: it is written now, as on the keep-local path, not
    /// left for a later re-sync a logout could preempt.
    func testASaveAfterTheAdoptsPersistIsWritten() throws {
        try bindAfterFirstSync()
        try save(marketing: false)
        let recordTs = try XCTUnwrap(storage.loadDecisionTs()) + 5
        network.getResult = .success(foundRecordJSON(marketing: false, updatedAt: recordTs))
        onReadPersisted = { [unowned self] in
            XCTAssertEqual(self.storage.loadDecisionTs(), recordTs, "the record was adopted")
            try? self.save(marketing: true)
        }

        try sync().get()

        XCTAssertEqual(storedMarketing(), true, "the save is kept, not filled or reported over")
        XCTAssertEqual(network.methods, [.post])
        let body = try XCTUnwrap(writtenBody())
        let prefs = try XCTUnwrap(body["consent_preferences"] as? [String: Any])
        let written = try XCTUnwrap(prefs["cookieOptions"] as? [String: Bool])
        XCTAssertEqual(written["dg-category-marketing"], true)
        let stamp = try XCTUnwrap(storage.loadDecisionTs())
        XCTAssertGreaterThan(stamp, recordTs)
        XCTAssertEqual((body["decision_ts"] as? NSNumber)?.int64Value, stamp)
    }

    /// On a LOGIN too: the persist already replaced local state with the record, so a save after it
    /// is a choice made over the record, and the login writes it (deliberately, unlike a save during
    /// a LOGIN's read, which the persist overwrites).
    func testASaveAfterALoginsAdoptPersistIsWritten() throws {
        let recordTs = ConsentStorage.nowSeconds() - 60
        network.getResult = .success(foundRecordJSON(marketing: false, updatedAt: recordTs))
        onReadPersisted = { [unowned self] in
            XCTAssertEqual(self.storage.loadDecisionTs(), recordTs, "the record was adopted")
            try? self.save(marketing: true)
        }

        try sync().get()

        XCTAssertNotNil(storage.loadBoundUserHash(), "the login bound")
        XCTAssertEqual(storedMarketing(), true, "the save is kept, not replaced by the record")
        XCTAssertEqual(network.methods, [.post])
        let body = try XCTUnwrap(writtenBody())
        let prefs = try XCTUnwrap(body["consent_preferences"] as? [String: Any])
        XCTAssertEqual((prefs["cookieOptions"] as? [String: Bool])?["dg-category-marketing"], true)
        let stamp = try XCTUnwrap(storage.loadDecisionTs())
        XCTAssertGreaterThan(stamp, recordTs)
        XCTAssertEqual((body["decision_ts"] as? NSNumber)?.int64Value, stamp)
    }

    /// The keep-local path adopts the record's CCPA flag with the record's time, as the adopt path
    /// does, so the next toggle here is stamped strictly after it.
    func testAKeepLocalReSyncAdoptsTheRecordsCcpaFlagWithItsTime() throws {
        try bindAfterFirstSync()
        try save(marketing: false)
        let recordTs = try XCTUnwrap(storage.loadDecisionTs()) - 60
        network.getResult = .success(foundRecordJSON(marketing: true, updatedAt: recordTs, ccpaOptout: true))

        try sync().get()

        XCTAssertEqual(storedMarketing(), false, "the newer local choice is kept")
        XCTAssertTrue(storage.loadCcpaOptout())
        XCTAssertEqual(storage.loadCcpaDecisionTs(), recordTs)
    }

    /// Re-sync with the read held open, save `marketing: true` while it is in flight, then answer it.
    private func resyncSavingDuringTheRead(_ record: Data) throws -> Result<Void, ConsentError> {
        network.deferGet = true
        let synced = expectation(description: "sync")
        var outcome: Result<Void, ConsentError> = .failure(.notInitialized)
        sut.syncUserIdentifier(
            userA,
            apiKey: testApiKey,
            trackingSignal: .authorized,
            getSignature: { payload, done in
                self.signedPayloads.append(payload)
                done(.success(UniversalConsentSignature(signature: "sig", keyId: "k1")))
            },
            completion: { result in
                outcome = result
                synced.fulfill()
            }
        )
        let pendingGet = try XCTUnwrap(network.pendingGetCompletion)
        network.deferGet = false
        try save(marketing: true)
        pendingGet(.success(record))
        wait(for: [synced], timeout: 1.0)
        return outcome
    }
}
