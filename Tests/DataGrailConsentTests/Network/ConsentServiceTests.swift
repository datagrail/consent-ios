@testable import DataGrailConsent
import XCTest

final class ConsentServiceTests: XCTestCase {
    var mockNetworkClient: MockNetworkClient!
    var mockStorage: MockConsentStorage!
    var service: ConsentService!
    let testPrivacyDomain = "consent.test.com"

    override func setUp() {
        super.setUp()
        mockNetworkClient = MockNetworkClient()
        mockStorage = MockConsentStorage()
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

    func testSavePreferencesSuccess() {
        let expectation = expectation(description: "savePreferences completes")

        mockNetworkClient.requestResult = .success(Data())
        mockStorage.uniqueId = "test-id-123"

        let preferences = ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "category_marketing", isEnabled: true),
            ]
        )

        let config = createTestConfig()

        service.savePreferences(preferences: preferences, config: config) { result in
            switch result {
            case .success:
                XCTAssertTrue(self.mockNetworkClient.requestCalled)
                XCTAssertEqual(self.mockNetworkClient.lastMethod, .post)
                XCTAssertTrue(self.mockNetworkClient.lastURL?.absoluteString.contains("/save_preferences") ?? false)
            case let .failure(error):
                XCTFail("Expected success but got error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testSavePreferencesQueuesOnFailure() {
        let expectation = expectation(description: "savePreferences queues on failure")

        mockNetworkClient.requestResult = .failure(.networkError("Connection failed"))
        mockStorage.uniqueId = "test-id-123"

        let preferences = ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "category_marketing", isEnabled: true),
            ]
        )

        let config = createTestConfig()

        service.savePreferences(preferences: preferences, config: config) { result in
            switch result {
            case .success:
                XCTFail("Expected failure but got success")
            case .failure:
                // Verify event was queued
                XCTAssertTrue(self.mockStorage.savePendingEventsCalled)
                XCTAssertFalse(self.mockStorage.lastPendingEvents.isEmpty)
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testSaveOpenSuccess() {
        let expectation = expectation(description: "saveOpen completes")

        mockNetworkClient.requestResult = .success(Data())
        mockStorage.uniqueId = "test-id-123"

        let config = createTestConfig()

        service.saveOpen(config: config) { result in
            switch result {
            case .success:
                XCTAssertTrue(self.mockNetworkClient.requestCalled)
                XCTAssertEqual(self.mockNetworkClient.lastMethod, .get)
                XCTAssertTrue(self.mockNetworkClient.lastURL?.absoluteString.contains("/save_open") ?? false)
                XCTAssertTrue(self.mockNetworkClient.lastURL?.absoluteString.contains("dg_customer_id=") ?? false)
            case let .failure(error):
                XCTFail("Expected success but got error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - Helper Methods

    private func createTestConfig() -> ConsentConfig {
        ConsentConfig(
            version: "1.0.0",
            consentContainerVersionId: "container1",
            dgCustomerId: "customer123",
            publishDate: 0,
            dch: "categorize",
            dc: "dg-category-essential",
            privacyDomain: testPrivacyDomain,
            plugins: Plugins(
                scriptControl: false,
                allCookieSubdomains: false,
                cookieBlocking: false,
                localStorageBlocking: false,
                syncOTConsent: false
            ),
            testMode: false,
            ignoreDoNotTrack: false,
            trackingDetailsUrl: "https://example.com/tracking",
            consentMode: "optin",
            showBanner: true,
            consentPolicy: ConsentPolicy(name: "GDPR", default: true),
            gppUsNat: false,
            initialCategories: InitialCategories(
                respectGpc: false,
                respectDnt: false,
                respectOptout: false,
                initial: ["dg-category-essential"],
                gpc: [],
                optout: []
            ),
            layout: Layout(
                id: "layout1",
                name: "Test Layout",
                description: nil,
                status: "published",
                defaultLayout: true,
                collapsedOnMobile: false,
                firstLayerId: "layer1",
                gpcDntLayerId: nil,
                consentLayers: [:]
            )
        )
    }
}

// MARK: - Mock Classes

class MockNetworkClient: NetworkClient {
    var requestCalled = false
    var requestResult: Result<Data, ConsentError> = .success(Data())
    var lastURL: URL?
    var lastMethod: HTTPMethod?
    var lastBody: Data?

    override func request(
        url: URL,
        method: HTTPMethod = .get,
        body: Data? = nil,
        headers _: [String: String]? = nil,
        completion: @escaping (Result<Data, ConsentError>) -> Void
    ) {
        requestCalled = true
        lastURL = url
        lastMethod = method
        lastBody = body
        completion(requestResult)
    }

    override func retryWithBackoff<T>(
        maxAttempts _: Int = 5,
        baseDelay _: TimeInterval = 0.25,
        operation: @escaping (@escaping (Result<T, ConsentError>) -> Void) -> Void,
        completion: @escaping (Result<T, ConsentError>) -> Void
    ) {
        // For testing, just call operation once without retry
        operation(completion)
    }
}

class MockConsentStorage: ConsentStorage {
    var uniqueId: String = "mock-unique-id"
    var pendingEvents: [[String: Any]] = []
    var savePendingEventsCalled = false
    var lastPendingEvents: [[String: Any]] = []

    init() {
        super.init()
    }

    override func getOrCreateUniqueId() -> String {
        uniqueId
    }

    override func loadPendingEvents() -> [[String: Any]] {
        pendingEvents
    }

    override func savePendingEvents(_ events: [[String: Any]]) throws {
        savePendingEventsCalled = true
        lastPendingEvents = events
        pendingEvents = events
    }
}
