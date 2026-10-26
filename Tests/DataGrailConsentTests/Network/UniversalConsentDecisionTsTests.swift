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
    private let testApiKey = "dg_live_test_key_123"
    private let privacyDomain = "consent.test.com"
    private let userA = "uc-opaque-id-7f3a9c"

    override func setUp() {
        super.setUp()
        storage = ConsentStorage()
        storage.clearAll()
        signedPayloads = []
        network = MethodAwareMockNetworkClient()
        sut = ConsentManager(
            storage: storage,
            configService: ConfigService(networkClient: network, storage: storage),
            consentService: ConsentService(networkClient: network, storage: storage, privacyDomain: privacyDomain)
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

    /// TRUST-2902 round 4: a re-sync that puts the user's own CCPA flag back after the rehydrate
    /// puts the setter's time back with it, so a later CCPA-only flush is not stamped now.
    func testWriteThroughKeepsTheSettersCcpaTime() throws {
        try bindAfterFirstSync()
        try save(marketing: false)
        let localTs = try XCTUnwrap(storage.loadDecisionTs())
        storage.saveCcpaChoice(true, now: 1_650_000_000)

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

        let expectation = expectation(description: "setCcpaOptout")
        sut.setCcpaOptout(true) { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(network.methods, [.post])
        // TRUST-2591 decision (2026-10-26), same body as consent-banner #756: the flag and its
        // provenance only. The category change is not resent; the next re-sync writes it.
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

    private func foundRecordJSON(marketing: Bool, updatedAt: Int64?) -> Data {
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
          "ccpa_optout": false\(updatedAtEntry)
        }
        """.utf8)
    }
}
