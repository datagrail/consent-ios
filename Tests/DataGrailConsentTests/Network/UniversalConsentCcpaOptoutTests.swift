@testable import DataGrailConsent
import XCTest

/// First-class `ccpa_optout` (TRUST-2591): the user's explicit "Do Not Sell or Share" choice, set
/// by the host app, never derived from a category or ATT, gated on the wire by `sync_optout`, and
/// replaced by a found record on login (TRUST-2902 rule). Same rule as the web/Android/RN SDKs.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class UniversalConsentCcpaOptoutTests: XCTestCase {
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
        makeSut(syncOptout: true)
    }

    override func tearDown() {
        storage.clearAll()
        sut = nil
        network = nil
        storage = nil
        super.tearDown()
    }

    // MARK: - Setter / getter

    func testDefaultsToFalseAndPersistsTheSetterValue() {
        XCTAssertFalse(sut.getCcpaOptout())

        XCTAssertNoThrow(try setCcpaOptout(true).get())
        XCTAssertTrue(sut.getCcpaOptout())
        XCTAssertTrue(storage.loadCcpaOptout())

        XCTAssertNoThrow(try setCcpaOptout(false).get())
        XCTAssertFalse(sut.getCcpaOptout())
    }

    func testSetterChangesNoCategoryAndIsLocalOnlyWhenUnbound() throws {
        try storage.savePreferences(marketingChoice(true))

        XCTAssertNoThrow(try setCcpaOptout(true).get())

        XCTAssertEqual(storage.loadPreferences(), marketingChoice(true))
        XCTAssertTrue(network.methods.isEmpty)
    }

    func testSetterWritesThroughWhenBoundWithGateOn() throws {
        try storage.savePreferences(marketingChoice(true))
        network.getResult = .success(notFound)
        XCTAssertNoThrow(try sync(userA).get())
        XCTAssertEqual(network.methods, [.get, .post])
        XCTAssertEqual(writtenCcpaOptout(), false)

        XCTAssertNoThrow(try setCcpaOptout(true).get())

        XCTAssertEqual(network.methods, [.get, .post, .post])
        XCTAssertEqual(writtenCcpaOptout(), true)
        XCTAssertEqual(writtenCookieOptions()?["dg-category-marketing"], true, "RAW local categories ride along")
    }

    func testSetterStaysLocalWhenGateOff() throws {
        makeSut(syncOptout: false)
        try storage.savePreferences(marketingChoice(true))
        network.getResult = .success(notFound)
        XCTAssertNoThrow(try sync(userA).get())
        let callsAfterLogin = network.methods.count

        XCTAssertNoThrow(try setCcpaOptout(true).get())

        XCTAssertEqual(network.methods.count, callsAfterLogin)
        XCTAssertTrue(sut.getCcpaOptout())
    }

    func testSetterStaysLocalWhenBoundButNoSessionInThisProcess() throws {
        try storage.savePreferences(marketingChoice(true))
        storage.saveBoundUserHash(try hash(userA))

        XCTAssertNoThrow(try setCcpaOptout(true).get())

        XCTAssertTrue(network.methods.isEmpty)
        XCTAssertTrue(sut.getCcpaOptout())
    }

    // MARK: - Wire field

    func testWireFieldIsFalseWhenGateOffEvenWithLocalFlag() throws {
        makeSut(syncOptout: false)
        try storage.savePreferences(marketingChoice(true))
        storage.saveCcpaOptout(true)
        network.getResult = .success(notFound)

        XCTAssertNoThrow(try sync(userA).get())

        XCTAssertEqual(writtenCcpaOptout(), false)
    }

    func testWireFieldIsNeverDerivedFromMarketingOrATT() throws {
        try storage.savePreferences(marketingChoice(false))
        network.getResult = .success(notFound)

        XCTAssertNoThrow(try sync(userA, trackingSignal: .denied).get())

        XCTAssertEqual(network.methods, [.get, .post])
        XCTAssertEqual(writtenCcpaOptout(), false)
        XCTAssertFalse(sut.getCcpaOptout())
    }

    func testResyncWriteThroughCarriesTheLocalFlagNotTheRecord() throws {
        storage.saveBoundUserHash(try hash(userA))
        try storage.savePreferences(marketingChoice(true))
        storage.saveCcpaOptout(true)
        network.getResult = .success(foundRecordJSON(marketing: false, ccpaOptout: false))

        XCTAssertNoThrow(try sync(userA).get())

        XCTAssertEqual(network.methods, [.get, .post])
        XCTAssertEqual(writtenCcpaOptout(), true)
        XCTAssertTrue(sut.getCcpaOptout())
    }

    func testResyncAdoptTakesTheRecordValueWithGateOn() throws {
        storage.saveBoundUserHash(try hash(userA))
        network.getResult = .success(foundRecordJSON(marketing: true, ccpaOptout: true))

        XCTAssertNoThrow(try sync(userA).get())

        XCTAssertEqual(network.methods, [.get])
        XCTAssertTrue(sut.getCcpaOptout())
    }

    func testResyncAdoptKeepsALocalOnlyFlagWithGateOff() throws {
        makeSut(syncOptout: false)
        storage.saveBoundUserHash(try hash(userA))
        storage.saveCcpaOptout(true)
        network.getResult = .success(foundRecordJSON(marketing: true, ccpaOptout: false))

        XCTAssertNoThrow(try sync(userA).get())

        XCTAssertEqual(network.methods, [.get])
        XCTAssertTrue(sut.getCcpaOptout())
    }

    // MARK: - Login (TRUST-2902 rule)

    func testLoginFoundRecordReplacesAPreLoginFlagWithoutWriting() throws {
        try storage.savePreferences(marketingChoice(true))
        storage.saveCcpaOptout(true)
        network.getResult = .success(foundRecordJSON(marketing: true, ccpaOptout: false))

        XCTAssertNoThrow(try sync(userA).get())

        XCTAssertEqual(network.methods, [.get])
        XCTAssertFalse(sut.getCcpaOptout())
    }

    func testLoginFoundRecordCarryingTrueIsAdopted() throws {
        network.getResult = .success(foundRecordJSON(marketing: true, ccpaOptout: true))

        XCTAssertNoThrow(try sync(userA).get())

        XCTAssertTrue(sut.getCcpaOptout())
    }

    func testLoginFoundSignalOnlyRecordStillReplacesTheFlag() throws {
        storage.saveCcpaOptout(true)
        network.getResult = .success(Data(#"{"status":"found","ccpa_optout":false,"gpc":false}"#.utf8))

        XCTAssertNoThrow(try sync(userA).get())

        XCTAssertEqual(network.methods, [.get])
        XCTAssertFalse(sut.getCcpaOptout())
    }

    func testLoginMissWithExplicitChoiceAttachesTheFlag() throws {
        try storage.savePreferences(marketingChoice(true))
        storage.saveCcpaOptout(true)
        network.getResult = .success(notFound)

        XCTAssertNoThrow(try sync(userA).get())

        XCTAssertEqual(network.methods, [.get, .post])
        XCTAssertEqual(writtenCcpaOptout(), true)
    }

    func testLoginMissWithOnlyASetterCallWritesNothing() throws {
        XCTAssertNoThrow(try setCcpaOptout(true).get())
        network.getResult = .success(notFound)

        XCTAssertNoThrow(try sync(userA).get())

        XCTAssertEqual(network.methods, [.get])
        XCTAssertTrue(sut.getCcpaOptout(), "stays local")
        XCTAssertNil(storage.loadPreferences())
    }

    func testLoginMissWhileBoundToAnotherIdentityClearsTheFlag() throws {
        storage.saveBoundUserHash(try hash(userA))
        storage.saveCcpaOptout(true)
        network.getResult = .success(notFound)

        XCTAssertNoThrow(try sync(userB).get())

        XCTAssertEqual(network.methods, [.get])
        XCTAssertFalse(sut.getCcpaOptout())
    }

    // MARK: - Neutral / reset

    func testClearUserIdentifierResetsTheFlag() throws {
        storage.saveBoundUserHash(try hash(userA))
        storage.saveCcpaOptout(true)

        sut.clearUserIdentifier()

        XCTAssertFalse(sut.getCcpaOptout())
        XCTAssertTrue(network.methods.isEmpty)
    }

    func testResetWipesTheFlag() {
        storage.saveCcpaOptout(true)

        sut.reset()

        XCTAssertFalse(storage.loadCcpaOptout())
    }

    // MARK: - Helpers

    private let notFound = Data(#"{"status":"not_found"}"#.utf8)

    private func makeSut(syncOptout: Bool) {
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
        let config = UCFixtures.makeConfig(privacyDomain: privacyDomain, syncOptout: syncOptout)
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

    private func sync(
        _ identifier: String,
        trackingSignal: TrackingSignal = .authorized
    ) -> Result<Void, ConsentError> {
        let expectation = expectation(description: "sync \(identifier)")
        var outcome: Result<Void, ConsentError> = .failure(.notInitialized)
        sut.syncUserIdentifier(
            identifier,
            apiKey: testApiKey,
            trackingSignal: trackingSignal,
            getSignature: nil
        ) { result in
            outcome = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        return outcome
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

    private func writtenJSON() -> [String: Any]? {
        guard let body = network.lastPostBody else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }

    private func writtenCcpaOptout() -> Bool? {
        writtenJSON()?["ccpa_optout"] as? Bool
    }

    private func writtenCookieOptions() -> [String: Bool]? {
        (writtenJSON()?["consent_preferences"] as? [String: Any])?["cookieOptions"] as? [String: Bool]
    }

    private func hash(_ identifier: String) throws -> String {
        try ConsentService.validatedUserHash(identifier: identifier, config: XCTUnwrap(sut.config))
    }

    private func marketingChoice(_ enabled: Bool) -> ConsentPreferences {
        ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "dg-category-essential", isEnabled: true),
                CategoryConsent(gtmKey: "dg-category-marketing", isEnabled: enabled),
            ]
        )
    }

    private func foundRecordJSON(marketing: Bool, ccpaOptout: Bool) -> Data {
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
          "gpc": false,
          "ccpa_optout": \(ccpaOptout)
        }
        """.utf8)
    }
}
