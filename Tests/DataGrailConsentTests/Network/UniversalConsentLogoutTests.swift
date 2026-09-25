@testable import DataGrailConsent
import XCTest

/// Shared-device login/logout for Universal Consent (TRUST-2902).
///
/// Covers the logout-to-neutral API (`clearUserIdentifier`) and the login rule: a found record
/// wins with no write; with no record only an explicit, unbound local choice is written; state
/// left by a different bound identity is never written and returns to neutral.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class UniversalConsentLogoutTests: XCTestCase {
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
        loadUniversalConsentConfig()
        network.methods = []
    }

    override func tearDown() {
        storage.clearAll()
        sut = nil
        network = nil
        storage = nil
        super.tearDown()
    }

    // MARK: - clearUserIdentifier

    func testClearUserIdentifierReturnsToNeutralWithoutTouchingOtherState() throws {
        let config = try XCTUnwrap(sut.config)
        try storage.savePreferences(marketingChoice(true))
        storage.saveBoundUserHash(try hash(userA))
        let uniqueId = storage.getOrCreateUniqueId()
        try storage.saveConfigCache(config)
        storage.saveConfigVersion(config.version)
        storage.saveLocaleCode("fr")
        try storage.savePendingEvents([["endpoint": "/save_preferences"]])

        let effective = sut.clearUserIdentifier()

        // Binding cleared; reads back to the config default, exactly as a fresh install.
        XCTAssertNil(storage.loadBoundUserHash())
        XCTAssertNil(storage.loadPreferences())
        XCTAssertFalse(sut.hasUserConsent())
        XCTAssertTrue(sut.shouldDisplayBanner())
        XCTAssertEqual(effective, sut.getDefaultPreferences(), "hands back the default for the listener")
        XCTAssertEqual(sut.getCategories(), sut.getDefaultPreferences())
        // Non-destructive: everything else survives and the SDK stays initialized.
        XCTAssertEqual(storage.getOrCreateUniqueId(), uniqueId)
        XCTAssertNotNil(storage.loadConfigCache())
        XCTAssertEqual(storage.loadConfigVersion(), config.version)
        XCTAssertEqual(storage.loadLocaleCode(), "fr")
        XCTAssertEqual(storage.loadPendingEvents().count, 1)
        XCTAssertNotNil(sut.config)
        // No network request: the server-side record is not deleted or modified.
        XCTAssertTrue(network.methods.isEmpty)
    }

    func testClearUserIdentifierIsIdempotentWhenUnbound() {
        XCTAssertNil(storage.loadBoundUserHash())
        sut.clearUserIdentifier()
        let effective = sut.clearUserIdentifier()

        XCTAssertNil(storage.loadBoundUserHash())
        XCTAssertEqual(effective, sut.getDefaultPreferences())
        XCTAssertTrue(network.methods.isEmpty)
    }

    func testResetClearsTheBinding() throws {
        storage.saveBoundUserHash(try hash(userA))
        sut.reset()
        XCTAssertNil(storage.loadBoundUserHash())
    }

    // MARK: - Login (device unbound): the four required cases

    func testLoginWithRecordAndExplicitLocalChoiceAdoptsTheRecordWithoutWriting() throws {
        try storage.savePreferences(marketingChoice(false))
        network.getResult = .success(foundRecordJSON(marketing: true))

        var rehydrated: ConsentPreferences?
        let result = sync(userA) { rehydrated = $0 }

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(network.methods, [.get], "the record wins; the pre-login choice is not written")
        XCTAssertTrue(sut.isCategoryEnabled("dg-category-marketing"), "record adopted locally")
        XCTAssertNotNil(rehydrated, "listener fired with the adopted state")
        XCTAssertEqual(storage.loadBoundUserHash(), try hash(userA))
    }

    func testLoginWithRecordAndNoLocalChoiceAdoptsTheRecordWithoutWriting() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))

        let result = sync(userA)

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(network.methods, [.get])
        XCTAssertTrue(sut.isCategoryEnabled("dg-category-marketing"))
        XCTAssertFalse(sut.shouldDisplayBanner())
        XCTAssertEqual(storage.loadBoundUserHash(), try hash(userA))
    }

    func testLoginWithNoRecordWritesTheExplicitLocalChoice() throws {
        try storage.savePreferences(marketingChoice(true))
        network.getResult = .success(notFound)

        let result = sync(userA)

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(network.methods, [.get, .post], "an explicit unbound choice is attached")
        XCTAssertEqual(writtenCookieOptions()?["dg-category-marketing"], true, "the RAW local choice")
        XCTAssertEqual(storage.loadPreferences(), marketingChoice(true), "local choice kept")
        XCTAssertEqual(storage.loadBoundUserHash(), try hash(userA))
    }

    func testLoginWithNoRecordAndDefaultsOnlyWritesNothingAndSucceeds() throws {
        network.getResult = .success(notFound)

        let result = sync(userA)

        // Formerly the "No consent preferences to sync" failure; now a successful no-write.
        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(network.methods, [.get], "config defaults are never written")
        XCTAssertNil(storage.loadPreferences(), "local unchanged")
        XCTAssertTrue(sut.shouldDisplayBanner())
        XCTAssertEqual(storage.loadBoundUserHash(), try hash(userA))
    }

    // MARK: - Shared-device switch and re-sync

    func testSwitchingUsersOnASharedDeviceDoesNotWriteThePreviousUsersState() throws {
        storage.saveBoundUserHash(try hash(userA))
        try storage.savePreferences(marketingChoice(true))
        network.getResult = .success(notFound)

        var rehydrated: ConsentPreferences?
        let result = sync(userB) { rehydrated = $0 }

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(network.methods, [.get], "user A's state is not written to user B's record")
        XCTAssertNil(storage.loadPreferences(), "A's state does not linger for B")
        XCTAssertTrue(sut.shouldDisplayBanner())
        XCTAssertEqual(rehydrated, sut.getDefaultPreferences(), "listener gets the neutral default")
        XCTAssertEqual(storage.loadBoundUserHash(), try hash(userB))
    }

    func testResyncWithRecordWritesThroughAGenuineLocalChange() throws {
        storage.saveBoundUserHash(try hash(userA))
        try storage.savePreferences(marketingChoice(false))
        network.getResult = .success(foundRecordJSON(marketing: true))

        let result = sync(userA)

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(network.methods, [.get, .post], "sync-on-change while logged in, unchanged")
        XCTAssertEqual(writtenCookieOptions()?["dg-category-marketing"], false)
    }

    func testResyncWithRecordEqualToLocalChoiceDoesNotRewrite() throws {
        storage.saveBoundUserHash(try hash(userA))
        try storage.savePreferences(marketingChoice(true))
        network.getResult = .success(foundRecordJSON(marketing: true))

        XCTAssertNoThrow(try sync(userA).get())
        XCTAssertEqual(network.methods, [.get])
    }

    func testResyncWithNoRecordWritesTheExplicitLocalChoice() throws {
        storage.saveBoundUserHash(try hash(userA))
        try storage.savePreferences(marketingChoice(false))
        network.getResult = .success(notFound)

        XCTAssertNoThrow(try sync(userA).get())
        XCTAssertEqual(network.methods, [.get, .post])
        XCTAssertEqual(storage.loadBoundUserHash(), try hash(userA))
    }

    // MARK: - Failures never bind or write

    func testFailedSeedWriteDoesNotBind() throws {
        try storage.savePreferences(marketingChoice(true))
        network.getResult = .success(notFound)
        network.postResult = .failure(.httpError(statusCode: 500, message: "boom"))

        let result = sync(userA)

        guard case .failure = result else { return XCTFail("Expected the write failure") }
        XCTAssertNil(storage.loadBoundUserHash(), "a retry must still be recognised as a login")
    }

    func testReadFailureLeavesTheBindingUnchanged() throws {
        storage.saveBoundUserHash(try hash(userA))
        try storage.savePreferences(marketingChoice(true))
        network.getResult = .failure(.networkError("offline"))

        let result = sync(userB)

        guard case .failure = result else { return XCTFail("Expected the read failure") }
        XCTAssertEqual(network.methods, [.get], "no write after a failed read")
        XCTAssertEqual(storage.loadBoundUserHash(), try hash(userA))
        XCTAssertEqual(storage.loadPreferences(), marketingChoice(true), "local state untouched")
    }

    // MARK: - Helpers

    private let notFound = Data(#"{"status":"not_found"}"#.utf8)

    private func sync(
        _ identifier: String,
        onRehydrated: ((ConsentPreferences) -> Void)? = nil
    ) -> Result<Void, ConsentError> {
        let expectation = expectation(description: "sync \(identifier)")
        var outcome: Result<Void, ConsentError> = .failure(.notInitialized)
        sut.syncUserIdentifier(
            identifier,
            apiKey: testApiKey,
            trackingSignal: .authorized,
            onRehydrated: onRehydrated
        ) { result in
            outcome = result
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        return outcome
    }

    private func writtenCookieOptions() -> [String: Bool]? {
        guard let body = network.lastPostBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let prefs = json["consent_preferences"] as? [String: Any]
        else { return nil }
        return prefs["cookieOptions"] as? [String: Bool]
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

    private func loadUniversalConsentConfig() {
        guard let data = try? JSONEncoder().encode(UCFixtures.makeConfig(privacyDomain: privacyDomain)),
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
    }

    private func foundRecordJSON(marketing: Bool) -> Data {
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
          "gpc": false
        }
        """.utf8)
    }
}

/// Answers GETs and POSTs independently and records every method, so a test can assert that a
/// read happened with no write after it (the shared UC mock only keeps the last request).
final class MethodAwareMockNetworkClient: NetworkClient {
    var getResult: Result<Data, ConsentError> = .success(Data())
    var postResult: Result<Data, ConsentError> = .success(Data(#"{"status":"ok"}"#.utf8))
    var methods: [HTTPMethod] = []
    var lastPostBody: Data?

    override func request(
        url _: URL,
        method: HTTPMethod = .get,
        body: Data? = nil,
        headers _: [String: String]? = nil,
        completion: @escaping (Result<Data, ConsentError>) -> Void
    ) {
        methods.append(method)
        if method == .post { lastPostBody = body }
        completion(method == .get ? getResult : postResult)
    }

    override func retryWithBackoff<T>(
        maxAttempts _: Int = 5,
        baseDelay _: TimeInterval = 0.25,
        shouldRetry _: @escaping (ConsentError) -> Bool = { _ in true },
        operation: @escaping (@escaping (Result<T, ConsentError>) -> Void) -> Void,
        completion: @escaping (Result<T, ConsentError>) -> Void
    ) {
        operation(completion)
    }
}
