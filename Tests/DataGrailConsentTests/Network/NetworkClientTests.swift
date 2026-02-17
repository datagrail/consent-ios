import XCTest

@testable import DataGrailConsent

// Suppress deprecation warnings for URLSession mocking - this is intentional for testing
// swiftlint:disable force_unwrapping non_optional_string_data_conversion
@available(
    iOS, deprecated: 13.0, message: "URLSession subclassing deprecated but needed for mocking"
)
@available(
    macOS, deprecated: 10.15, message: "URLSession subclassing deprecated but needed for mocking"
)
final class NetworkClientTests: XCTestCase {
    var sut: NetworkClient!
    var mockSession: MockURLSession!

    override func setUp() {
        super.setUp()
        mockSession = MockURLSession()
        sut = NetworkClient(session: mockSession)
    }

    override func tearDown() {
        sut = nil
        mockSession = nil
        super.tearDown()
    }

    // MARK: - Request Tests

    func testRequestSuccess() {
        // Given
        let expectedData = "test response".data(using: .utf8)!
        mockSession.mockData = expectedData
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )

        let expectation = XCTestExpectation(description: "Request completes")
        var receivedResult: Result<Data, ConsentError>?

        // When
        sut.request(url: URL(string: "https://example.com")!) { result in
            receivedResult = result
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 1.0)

        guard case let .success(data) = receivedResult else {
            XCTFail("Expected success but got failure")
            return
        }

        XCTAssertEqual(data, expectedData)
    }

    func testRequestWithPOSTMethod() {
        // Given
        let requestBody = "{\"key\":\"value\"}".data(using: .utf8)!
        mockSession.mockData = Data()
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )

        let expectation = XCTestExpectation(description: "Request completes")

        // When
        sut.request(
            url: URL(string: "https://example.com")!,
            method: .post,
            body: requestBody
        ) { _ in
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 1.0)

        let request = mockSession.lastRequest
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.httpBody, requestBody)
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testRequestWithCustomHeaders() {
        // Given
        let headers = ["Authorization": "Bearer token", "X-Custom": "value"]
        mockSession.mockData = Data()
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )

        let expectation = XCTestExpectation(description: "Request completes")

        // When
        sut.request(
            url: URL(string: "https://example.com")!,
            headers: headers
        ) { _ in
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 1.0)

        let request = mockSession.lastRequest
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-Custom"), "value")
    }

    func testRequestNetworkError() {
        // Given
        mockSession.mockError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: nil
        )

        let expectation = XCTestExpectation(description: "Request completes")
        var receivedResult: Result<Data, ConsentError>?

        // When
        sut.request(url: URL(string: "https://example.com")!) { result in
            receivedResult = result
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 1.0)

        guard case let .failure(error) = receivedResult,
              case .networkError = error
        else {
            XCTFail("Expected network error")
            return
        }
    }

    func testRequestHTTPError() {
        // Given
        mockSession.mockData = Data()
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )

        let expectation = XCTestExpectation(description: "Request completes")
        var receivedResult: Result<Data, ConsentError>?

        // When
        sut.request(url: URL(string: "https://example.com")!) { result in
            receivedResult = result
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 1.0)

        guard case let .failure(error) = receivedResult,
              case let .networkError(message) = error
        else {
            XCTFail("Expected network error")
            return
        }

        XCTAssertTrue(message.contains("404"))
    }

    func testRequestNoData() {
        // Given
        mockSession.mockData = nil
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )

        let expectation = XCTestExpectation(description: "Request completes")
        var receivedResult: Result<Data, ConsentError>?

        // When
        sut.request(url: URL(string: "https://example.com")!) { result in
            receivedResult = result
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 1.0)

        guard case let .failure(error) = receivedResult,
              case let .networkError(message) = error
        else {
            XCTFail("Expected network error")
            return
        }

        XCTAssertTrue(message.contains("No data"))
    }

    // MARK: - Retry Tests

    func testRetrySuccessOnFirstAttempt() {
        // Given
        let expectedValue = "success"
        let expectation = XCTestExpectation(description: "Retry completes")
        var receivedResult: Result<String, ConsentError>?
        var attemptCount = 0

        // When
        sut.retryWithBackoff(maxAttempts: 3, baseDelay: 0.01) { completion in
            attemptCount += 1
            completion(.success(expectedValue))
        } completion: { result in
            receivedResult = result
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(attemptCount, 1)
        guard case let .success(value) = receivedResult else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(value, expectedValue)
    }

    func testRetrySuccessOnSecondAttempt() {
        // Given
        let expectedValue = "success"
        let expectation = XCTestExpectation(description: "Retry completes")
        var receivedResult: Result<String, ConsentError>?
        var attemptCount = 0

        // When
        sut.retryWithBackoff(
            maxAttempts: 3, baseDelay: 0.01,
            operation: { completion in
                attemptCount += 1
                if attemptCount == 1 {
                    completion(.failure(.networkError("Temporary failure")))
                } else {
                    completion(.success(expectedValue))
                }
            },
            completion: { (result: Result<String, ConsentError>) in
                receivedResult = result
                expectation.fulfill()
            }
        )

        // Then
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(attemptCount, 2)
        guard case let .success(value) = receivedResult else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(value, expectedValue)
    }

    func testRetryFailureAfterMaxAttempts() {
        // Given
        let expectation = XCTestExpectation(description: "Retry completes")
        var receivedResult: Result<String, ConsentError>?
        var attemptCount = 0

        // When
        sut.retryWithBackoff(
            maxAttempts: 3, baseDelay: 0.01,
            operation: { completion in
                attemptCount += 1
                completion(.failure(.networkError("Persistent failure")))
            },
            completion: { (result: Result<String, ConsentError>) in
                receivedResult = result
                expectation.fulfill()
            }
        )

        // Then
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(attemptCount, 3)
        guard case let .failure(error) = receivedResult,
              case let .networkError(message) = error
        else {
            XCTFail("Expected failure")
            return
        }
        XCTAssertEqual(message, "Persistent failure")
    }

    func testRetryExponentialBackoff() {
        // Given
        let expectation = XCTestExpectation(description: "Retry completes")
        var attemptTimes: [Date] = []

        // When
        sut.retryWithBackoff(
            maxAttempts: 3, baseDelay: 0.1,
            operation: { completion in
                attemptTimes.append(Date())
                completion(.failure(.networkError("Always fail")))
            },
            completion: { (_: Result<String, ConsentError>) in
                expectation.fulfill()
            }
        )

        // Then
        wait(for: [expectation], timeout: 2.0)

        XCTAssertEqual(attemptTimes.count, 3)

        if attemptTimes.count == 3 {
            // First to second attempt: ~0.1s (baseDelay * 2^0)
            let delay1 = attemptTimes[1].timeIntervalSince(attemptTimes[0])
            XCTAssertGreaterThan(delay1, 0.09)
            XCTAssertLessThan(delay1, 1.0) // Very lenient for slow CI workers

            // Second to third attempt: ~0.2s (baseDelay * 2^1)
            let delay2 = attemptTimes[2].timeIntervalSince(attemptTimes[1])
            XCTAssertGreaterThan(delay2, 0.19)
            XCTAssertLessThan(delay2, 1.0) // Very lenient for slow CI workers

            // Key assertion: second delay should be longer than first (exponential backoff)
            XCTAssertGreaterThan(delay2, delay1, "Exponential backoff should increase delay")
        }
    }
}

// MARK: - Mock URLSession

@available(iOS, deprecated: 13.0, message: "Intentional for mocking")
@available(macOS, deprecated: 10.15, message: "Intentional for mocking")
class MockURLSession: URLSession, @unchecked Sendable {
    var mockData: Data?
    var mockResponse: URLResponse?
    var mockError: Error?
    var lastRequest: URLRequest?

    override func dataTask(
        with request: URLRequest,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        lastRequest = request
        return MockURLSessionDataTask {
            completionHandler(self.mockData, self.mockResponse, self.mockError)
        }
    }
}

@available(iOS, deprecated: 13.0, message: "Intentional for mocking")
@available(macOS, deprecated: 10.15, message: "Intentional for mocking")
class MockURLSessionDataTask: URLSessionDataTask, @unchecked Sendable {
    private let closure: () -> Void

    init(closure: @escaping () -> Void) {
        self.closure = closure
    }

    override func resume() {
        closure()
    }
}
