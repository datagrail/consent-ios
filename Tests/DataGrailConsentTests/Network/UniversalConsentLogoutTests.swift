@testable import DataGrailConsent
import XCTest

/// Shared-device login/logout for Universal Consent (TRUST-2902).
///
/// Covers the logout-to-neutral API (`clearUserIdentifier`) and the rule that a genuine-miss
/// login transition does not attribute pre-login anonymous consent to the new identity unless
/// the host opts in with `attachAnonymousConsent`.
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

    // MARK: - Genuine miss: no anonymous-history attribution

    func testFirstLoginMissWithLocalChoiceDoesNotWriteAndReturnsToNeutral() throws {
        try storage.savePreferences(marketingChoice(true))
        network.getResult = .success(notFound)

        var rehydrated: ConsentPreferences?
        let result = sync(userA) { rehydrated = $0 }

        XCTAssertNoThrow(try result.get(), "a suppressed attribution is not an error")
        XCTAssertEqual(network.methods, [.get], "pre-login choice is not POSTed to the new identity")
        XCTAssertNil(storage.loadPreferences())
        XCTAssertTrue(sut.shouldDisplayBanner())
        XCTAssertEqual(rehydrated, sut.getDefaultPreferences(), "listener gets the neutral default")
        XCTAssertEqual(storage.loadBoundUserHash(), try hash(userA))
    }

    func testFirstLoginMissWithOptInSeedsTheRecordFromTheLocalChoice() throws {
        try storage.savePreferences(marketingChoice(true))
        network.getResult = .success(notFound)

        let result = sync(userA, attachAnonymousConsent: true)

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(network.methods, [.get, .post])
        XCTAssertEqual(storage.loadPreferences(), marketingChoice(true), "local choice kept")
        XCTAssertEqual(storage.loadBoundUserHash(), try hash(userA))
    }

    func testAlreadyBoundMissWithLocalChoiceStillSyncs() throws {
        storage.saveBoundUserHash(try hash(userA))
        try storage.savePreferences(marketingChoice(false))
        network.getResult = .success(notFound)

        let result = sync(userA)

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(network.methods, [.get, .post], "sync-on-change still works while logged in")
        XCTAssertEqual(storage.loadBoundUserHash(), try hash(userA))
    }

    func testSwitchingUsersOnASharedDeviceDoesNotWriteThePreviousUsersChoice() throws {
        storage.saveBoundUserHash(try hash(userA))
        try storage.savePreferences(marketingChoice(true))
        network.getResult = .success(notFound)

        let result = sync(userB)

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(network.methods, [.get], "user A's choice is not written to user B's record")
        XCTAssertNil(storage.loadPreferences())
        XCTAssertEqual(storage.loadBoundUserHash(), try hash(userB))
    }

    func testMissWithoutLocalChoiceKeepsExistingBehaviorAndBinds() throws {
        network.getResult = .success(notFound)

        let result = sync(userA)

        // Unchanged: nothing to sync, no fabricated default is written.
        guard case .failure(.invalidConfiguration) = result else {
            return XCTFail("Expected the existing nothing-to-sync failure, got \(result)")
        }
        XCTAssertEqual(network.methods, [.get])
        // Bound, so the user's first in-app choice syncs on the next call instead of being
        // mistaken for anonymous history.
        XCTAssertEqual(storage.loadBoundUserHash(), try hash(userA))
    }

    func testFailedSeedWriteDoesNotBind() throws {
        try storage.savePreferences(marketingChoice(true))
        network.getResult = .success(notFound)
        network.postResult = .failure(.httpError(statusCode: 500, message: "boom"))

        let result = sync(userA, attachAnonymousConsent: true)

        guard case .failure = result else { return XCTFail("Expected the write failure") }
        XCTAssertNil(storage.loadBoundUserHash(), "a retry must still be recognised as a transition")
    }

    // MARK: - Found record and read failure

    func testFoundRecordBindsAndIsOtherwiseUnchanged() throws {
        network.getResult = .success(foundRecordJSON(marketing: true))

        let result = sync(userA)

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(network.methods, [.get], "adopt-without-POST, as before")
        XCTAssertTrue(sut.isCategoryEnabled("dg-category-marketing"))
        XCTAssertEqual(storage.loadBoundUserHash(), try hash(userA))
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
        attachAnonymousConsent: Bool = false,
        onRehydrated: ((ConsentPreferences) -> Void)? = nil
    ) -> Result<Void, ConsentError> {
        let expectation = expectation(description: "sync \(identifier)")
        var outcome: Result<Void, ConsentError> = .failure(.notInitialized)
        sut.syncUserIdentifier(
            identifier,
            apiKey: testApiKey,
            trackingSignal: .authorized,
            attachAnonymousConsent: attachAnonymousConsent,
            onRehydrated: onRehydrated
        ) { result in
            outcome = result
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        return outcome
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

    override func request(
        url _: URL,
        method: HTTPMethod = .get,
        body _: Data? = nil,
        headers _: [String: String]? = nil,
        completion: @escaping (Result<Data, ConsentError>) -> Void
    ) {
        methods.append(method)
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
