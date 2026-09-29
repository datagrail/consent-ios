@testable import DataGrailConsent
import XCTest

final class ConfigServiceTests: XCTestCase {
    private static let suiteName = "ConfigServiceTests"
    private let configUrl = URL(fileURLWithPath: "/config.json")

    var mockNetworkClient: MockNetworkClient!
    var storage: ConsentStorage!
    var sut: ConfigService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        UserDefaults.standard.removePersistentDomain(forName: Self.suiteName)
        mockNetworkClient = MockNetworkClient()
        storage = try ConsentStorage(userDefaults: XCTUnwrap(UserDefaults(suiteName: Self.suiteName)))
        sut = ConfigService(networkClient: mockNetworkClient, storage: storage)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: Self.suiteName)
        sut = nil
        storage = nil
        mockNetworkClient = nil
        super.tearDown()
    }

    // MARK: - Validation

    func testValidConfigSucceedsAndIsCached() throws {
        mockNetworkClient.requestResult = try .success(configData())

        let result = fetch()

        XCTAssertNoThrow(try result.get())
        XCTAssertNotNil(storage.loadConfigCache())
    }

    func testInvalidConfigWithCacheReturnsCacheWithoutOverwriting() throws {
        let cached = try seedCache(version: "cached-version")
        mockNetworkClient.requestResult = try .success(configData { $0["consentMode"] = "bogus" })

        let result = fetch()

        XCTAssertEqual(try result.get().version, cached.version)
        XCTAssertEqual(storage.loadConfigCache()?.version, cached.version)
    }

    func testInvalidConfigWithoutCacheFailsWithValidationErrorAndIsNotCached() throws {
        mockNetworkClient.requestResult = try .success(configData { json in
            var layout = json["layout"] as? [String: Any] ?? [:]
            layout["first_layer_id"] = "missing"
            json["layout"] = layout
        })

        let result = fetch()

        guard case let .failure(.validationError(message)) = result else {
            return XCTFail("Expected validationError, got \(result)")
        }
        XCTAssertTrue(message.contains("firstLayerId"))
        XCTAssertNil(storage.loadConfigCache())
    }

    func testMalformedJsonWithoutCacheFailsWithParseError() {
        mockNetworkClient.requestResult = .success(Data("{not json".utf8))

        guard case .failure(.parseError) = fetch() else {
            return XCTFail("Expected parseError")
        }
    }

    // MARK: - Network Failures

    func testNetworkFailureWithoutCacheReturnsOriginalError() {
        mockNetworkClient.requestResult = .failure(.networkError("offline"))

        guard case let .failure(.networkError(message)) = fetch() else {
            return XCTFail("Expected networkError")
        }
        XCTAssertEqual(message, "offline")
    }

    func testNetworkFailureWithCacheReturnsCache() throws {
        let cached = try seedCache(version: "cached-version")
        mockNetworkClient.requestResult = .failure(.networkError("offline"))

        XCTAssertEqual(try fetch().get().version, cached.version)
    }

    func testDefiniteClientErrorWithoutCacheFailsWithConfigNotPublished() {
        for statusCode in [400, 401, 403, 404, 410, 422] {
            mockNetworkClient.requestResult = .failure(.httpError(statusCode: statusCode, message: "rejected"))

            guard case let .failure(.configNotPublished(actual)) = fetch() else {
                XCTFail("Expected configNotPublished for HTTP \(statusCode)")
                continue
            }
            XCTAssertEqual(actual, statusCode)
        }
    }

    func testDefiniteClientErrorWithCacheReturnsCache() throws {
        let cached = try seedCache(version: "cached-version")
        for statusCode in [403, 404] {
            mockNetworkClient.requestResult = .failure(.httpError(statusCode: statusCode, message: "rejected"))

            XCTAssertEqual(try fetch().get().version, cached.version, "HTTP \(statusCode)")
        }
    }

    func testTransientHttpErrorsWithoutCacheKeepHttpError() {
        for statusCode in [408, 429, 500] {
            mockNetworkClient.requestResult = .failure(.httpError(statusCode: statusCode, message: "transient"))

            guard case let .failure(.httpError(actual, _)) = fetch() else {
                XCTFail("Expected httpError for HTTP \(statusCode)")
                continue
            }
            XCTAssertEqual(actual, statusCode)
        }
    }

    // MARK: - Retry Policy

    func testShouldRetryConfigFetch() {
        let notRetried: [ConsentError] = [
            .validationError("invalid"),
            .httpError(statusCode: 404, message: "missing"),
            .configNotPublished(statusCode: 403),
        ]
        for error in notRetried {
            XCTAssertFalse(ConfigService.shouldRetryConfigFetch(error), "\(error)")
        }

        let retried: [ConsentError] = [
            .parseError("truncated"),
            .networkError("offline"),
            .httpError(statusCode: 500, message: "server"),
            .httpError(statusCode: 429, message: "rate limited"),
            .httpError(statusCode: 408, message: "timeout"),
        ]
        for error in retried {
            XCTAssertTrue(ConfigService.shouldRetryConfigFetch(error), "\(error)")
        }
    }

    func testConfigNotPublishedIsNonRetryableClientErrorWithoutUrlInDescription() {
        for statusCode in [403, nil] {
            let error = ConsentError.configNotPublished(statusCode: statusCode)
            XCTAssertTrue(error.isClientError)
            XCTAssertFalse(ConsentError.isRetryable(error))
        }
        let withStatus = ConsentError.configNotPublished(statusCode: 403).errorDescription ?? ""
        let withoutStatus = ConsentError.configNotPublished(statusCode: nil).errorDescription ?? ""
        XCTAssertTrue(withStatus.contains("HTTP 403"))
        XCTAssertFalse(withoutStatus.contains("HTTP"))
        for description in [withStatus, withoutStatus] {
            XCTAssertFalse(description.contains("://"), "description must not include a URL")
        }
    }

    // MARK: - Helpers

    private func fetch() -> Result<ConsentConfig, ConsentError> {
        var captured: Result<ConsentConfig, ConsentError>?
        sut.fetchConfig(from: configUrl) { captured = $0 }
        guard let captured else {
            XCTFail("fetchConfig did not complete synchronously with MockNetworkClient")
            return .failure(.networkError("no result"))
        }
        return captured
    }

    private func configData(mutate: ((inout [String: Any]) -> Void)? = nil) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "test-config", withExtension: "json"))
        let data = try Data(contentsOf: url)
        guard let mutate else { return data }
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        mutate(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    @discardableResult
    private func seedCache(version: String) throws -> ConsentConfig {
        let config = try JSONDecoder().decode(ConsentConfig.self, from: configData { $0["version"] = version })
        try storage.saveConfigCache(config)
        return config
    }
}
