@testable import DataGrailConsent
import XCTest

/// `initialize(configUrl:onConfigError:completion:)` (TRUST-3254): a config refresh failure that the
/// cached config masked reaches the host, with the same error cases as an uncached failure. Parity
/// with consent-react `onConfigError` (TRUST-2745).
final class ConfigErrorHandlerTests: XCTestCase {
    private let suiteName = "ConfigErrorHandlerTests"
    private var storage: ConsentStorage!
    private var network: DeferrableNetworkClient!
    private var sut: DataGrailConsent!
    private var configUrl: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        storage = try ConsentStorage(userDefaults: XCTUnwrap(UserDefaults(suiteName: suiteName)))
        network = DeferrableNetworkClient()
        sut = DataGrailConsent()
        configUrl = try XCTUnwrap(URL(string: "https://consent.example.com/config.json"))
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        sut = nil
        network = nil
        storage = nil
        super.tearDown()
    }

    // MARK: - Reported: a failed refresh masked by the cache

    func testNetworkFailureWithACachedConfigIsReportedOnceOnMainBeforeCompletion() throws {
        try cacheConfig()
        network.result = .failure(.networkError("offline"))

        let outcome = try initialize()

        XCTAssertNoThrow(try outcome.result.get(), "the cached config is still served")
        XCTAssertEqual(outcome.errors.count, 1)
        guard case .networkError = outcome.errors.first else {
            return XCTFail("Expected networkError, got \(outcome.errors)")
        }
        XCTAssertEqual(outcome.order, ["onConfigError", "completion"])
    }

    func testDefinite4xxWithACachedConfigIsReportedAsConfigNotPublished() throws {
        try cacheConfig()
        network.result = .failure(.httpError(statusCode: 404, message: "Not Found"))

        let outcome = try initialize()

        XCTAssertNoThrow(try outcome.result.get())
        guard case .configNotPublished(statusCode: 404) = outcome.errors.first else {
            return XCTFail("Expected configNotPublished(404), got \(outcome.errors)")
        }
    }

    func testUnparseableBodyWithACachedConfigIsReportedAsParseError() throws {
        try cacheConfig()
        network.result = .success(Data("<html>not json</html>".utf8))

        let outcome = try initialize()

        guard case .parseError = outcome.errors.first else {

            return XCTFail("Expected parseError, got \(outcome.errors)")

        }
    }

    func testWellFormedJSONOfTheWrongShapeIsReportedAsParseErrorNotNetworkError() throws {
        try cacheConfig()
        network.result = .success(Data(#"{"unexpected": true}"#.utf8))

        let outcome = try initialize()

        guard case .parseError = outcome.errors.first else {

            return XCTFail("Expected parseError, got \(outcome.errors)")

        }
    }

    // MARK: - Not reported

    func testSuccessfulFetchIsNotReported() throws {
        try cacheConfig()
        network.result = try .success(configData())

        let outcome = try initialize()

        XCTAssertNoThrow(try outcome.result.get())
        XCTAssertTrue(outcome.errors.isEmpty)
    }

    func testNotModifiedServedFromTheCacheIsNotReported() throws {
        try cacheConfig()
        network.result = .success(Data())

        let outcome = try initialize()

        XCTAssertNoThrow(try outcome.result.get())
        XCTAssertTrue(outcome.errors.isEmpty)
    }

    func testFailureWithNoCachedConfigFailsInitializeInsteadOfReporting() throws {
        network.result = .failure(.networkError("offline"))

        let outcome = try initialize()

        guard case .failure(.networkError) = outcome.result else {

            return XCTFail("Expected networkError, got \(outcome.result)")

        }
        XCTAssertTrue(outcome.errors.isEmpty, "the initial-fetch failure surfaces through completion only")
    }

    func testResetBeforeTheFetchSettlesStopsReporting() throws {
        try cacheConfig()
        network.deferred = true
        var errors: [ConsentError] = []
        sut.initialize(
            configUrl: configUrl, networkClient: network, storage: storage,
            onConfigError: { errors.append($0) },
            completion: { _ in }
        )

        sut.reset()
        try XCTUnwrap(network.pending)(.failure(.networkError("offline")))
        drainMainQueue()

        XCTAssertTrue(errors.isEmpty)
    }

    func testASupersededSessionDoesNotReportIntoItsHandler() throws {
        try cacheConfig()
        network.deferred = true
        var firstErrors: [ConsentError] = []
        sut.initialize(
            configUrl: configUrl, networkClient: network, storage: storage,
            onConfigError: { firstErrors.append($0) },
            completion: { _ in }
        )
        let firstFetch = try XCTUnwrap(network.pending)

        network.deferred = false
        network.result = try .success(configData())
        _ = try initialize()
        firstFetch(.failure(.networkError("offline")))
        drainMainQueue()

        XCTAssertTrue(firstErrors.isEmpty)
    }

    // MARK: - Helpers

    private func configData() throws -> Data {
        let file = try XCTUnwrap(Bundle.module.url(forResource: "test-config", withExtension: "json"))
        return try Data(contentsOf: file)
    }

    private func cacheConfig() throws {
        try storage.saveConfigCache(JSONDecoder().decode(ConsentConfig.self, from: configData()))
    }

    private struct InitOutcome {
        let result: Result<Void, ConsentError>
        let errors: [ConsentError]
        let order: [String]
    }

    private func initialize() throws -> InitOutcome {
        var errors: [ConsentError] = []
        var order: [String] = []
        var captured: Result<Void, ConsentError>?
        let completed = expectation(description: "initialize completes")
        sut.initialize(
            configUrl: configUrl, networkClient: network, storage: storage,
            onConfigError: { error in
                XCTAssertTrue(Thread.isMainThread, "onConfigError runs on the main thread")
                errors.append(error)
                order.append("onConfigError")
            },
            completion: { result in
                captured = result
                order.append("completion")
                completed.fulfill()
            }
        )
        wait(for: [completed], timeout: 2.0)
        drainMainQueue()
        return try InitOutcome(result: XCTUnwrap(captured), errors: errors, order: order)
    }

    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1.0)
    }
}

/// Answers every request with `result`, or holds the completion in `pending` while `deferred`.
private final class DeferrableNetworkClient: NetworkClient {
    var result: Result<Data, ConsentError> = .success(Data())
    var deferred = false
    var pending: ((Result<Data, ConsentError>) -> Void)?

    override func request(
        url _: URL,
        method _: HTTPMethod = .get,
        body _: Data? = nil,
        headers _: [String: String]? = nil,
        completion: @escaping (Result<Data, ConsentError>) -> Void
    ) {
        if deferred {
            pending = completion
            return
        }
        completion(result)
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
