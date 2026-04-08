@testable import DataGrailConsent
import XCTest

final class LoggerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Reset log level before each test
        Logger.logLevel = .none
    }

    override func tearDown() {
        // Reset log level after each test
        Logger.logLevel = .none
        super.tearDown()
    }

    // MARK: - LogLevel Comparable Tests

    func testLogLevelComparableOrdering() {
        // Test that log levels are properly ordered from least to most verbose
        XCTAssertTrue(LogLevel.none < LogLevel.error)
        XCTAssertTrue(LogLevel.error < LogLevel.warn)
        XCTAssertTrue(LogLevel.warn < LogLevel.info)
        XCTAssertTrue(LogLevel.info < LogLevel.debug)

        // Test reflexive property (a level equals itself)
        XCTAssertFalse(LogLevel.error < LogLevel.error)
        XCTAssertFalse(LogLevel.warn < LogLevel.warn)

        // Test transitive property
        XCTAssertTrue(LogLevel.none < LogLevel.warn)
        XCTAssertTrue(LogLevel.error < LogLevel.info)
        XCTAssertTrue(LogLevel.none < LogLevel.debug)
    }

    func testLogLevelGreaterThanComparison() {
        XCTAssertTrue(LogLevel.debug > LogLevel.info)
        XCTAssertTrue(LogLevel.info > LogLevel.warn)
        XCTAssertTrue(LogLevel.warn > LogLevel.error)
        XCTAssertTrue(LogLevel.error > LogLevel.none)
    }

    func testLogLevelGreaterThanOrEqualComparison() {
        XCTAssertTrue(LogLevel.debug >= LogLevel.debug)
        XCTAssertTrue(LogLevel.debug >= LogLevel.info)
        XCTAssertTrue(LogLevel.warn >= LogLevel.error)
        XCTAssertTrue(LogLevel.error >= LogLevel.none)
    }

    func testLogLevelLessThanOrEqualComparison() {
        XCTAssertTrue(LogLevel.none <= LogLevel.none)
        XCTAssertTrue(LogLevel.none <= LogLevel.error)
        XCTAssertTrue(LogLevel.error <= LogLevel.warn)
        XCTAssertTrue(LogLevel.info <= LogLevel.debug)
    }

    // MARK: - Level Gating Tests

    func testLogLevelNoneBlocksAllMessages() {
        Logger.logLevel = .none

        // All logging methods should be blocked at .none level
        // We can't directly verify os_log output, but we can verify the level gating
        XCTAssertFalse(Logger.logLevel >= .error)
        XCTAssertFalse(Logger.logLevel >= .warn)
        XCTAssertFalse(Logger.logLevel >= .info)
        XCTAssertFalse(Logger.logLevel >= .debug)
    }

    func testLogLevelErrorAllowsOnlyErrors() {
        Logger.logLevel = .error

        XCTAssertTrue(Logger.logLevel >= .error)
        XCTAssertFalse(Logger.logLevel >= .warn)
        XCTAssertFalse(Logger.logLevel >= .info)
        XCTAssertFalse(Logger.logLevel >= .debug)
    }

    func testLogLevelWarnAllowsWarnAndError() {
        Logger.logLevel = .warn

        XCTAssertTrue(Logger.logLevel >= .error)
        XCTAssertTrue(Logger.logLevel >= .warn)
        XCTAssertFalse(Logger.logLevel >= .info)
        XCTAssertFalse(Logger.logLevel >= .debug)
    }

    func testLogLevelInfoAllowsInfoWarnAndError() {
        Logger.logLevel = .info

        XCTAssertTrue(Logger.logLevel >= .error)
        XCTAssertTrue(Logger.logLevel >= .warn)
        XCTAssertTrue(Logger.logLevel >= .info)
        XCTAssertFalse(Logger.logLevel >= .debug)
    }

    func testLogLevelDebugAllowsAllMessages() {
        Logger.logLevel = .debug

        XCTAssertTrue(Logger.logLevel >= .error)
        XCTAssertTrue(Logger.logLevel >= .warn)
        XCTAssertTrue(Logger.logLevel >= .info)
        XCTAssertTrue(Logger.logLevel >= .debug)
    }

    // MARK: - Public API Proxy Tests

    func testDataGrailConsentLogLevelPropagatesToLogger() {
        // Verify that setting the public API propagates to the internal Logger
        DataGrailConsent.logLevel = .debug
        XCTAssertEqual(Logger.logLevel, .debug)

        DataGrailConsent.logLevel = .warn
        XCTAssertEqual(Logger.logLevel, .warn)

        DataGrailConsent.logLevel = .none
        XCTAssertEqual(Logger.logLevel, .none)
    }

    func testDataGrailConsentLogLevelReadsFromLogger() {
        // Verify that reading from the public API reflects the internal Logger state
        Logger.logLevel = .error
        XCTAssertEqual(DataGrailConsent.logLevel, .error)

        Logger.logLevel = .info
        XCTAssertEqual(DataGrailConsent.logLevel, .info)
    }

    // MARK: - Thread Safety Tests

    func testConcurrentLogLevelAccess() {
        let iterations = 100
        let expectation = self.expectation(description: "Concurrent access completes")
        expectation.expectedFulfillmentCount = iterations * 2

        // Spawn multiple threads that read and write logLevel concurrently
        for i in 0..<iterations {
            DispatchQueue.global().async {
                let levels: [LogLevel] = [.none, .error, .warn, .info, .debug]
                Logger.logLevel = levels[i % levels.count]
                expectation.fulfill()
            }

            DispatchQueue.global().async {
                _ = Logger.logLevel
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
        // Test passes if no crashes occur from concurrent access
    }

    func testConcurrentPublicAPIAccess() {
        let iterations = 100
        let expectation = self.expectation(description: "Concurrent public API access completes")
        expectation.expectedFulfillmentCount = iterations * 2

        // Spawn multiple threads that read and write via public API concurrently
        for i in 0..<iterations {
            DispatchQueue.global().async {
                let levels: [LogLevel] = [.none, .error, .warn, .info, .debug]
                DataGrailConsent.logLevel = levels[i % levels.count]
                expectation.fulfill()
            }

            DispatchQueue.global().async {
                _ = DataGrailConsent.logLevel
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
        // Test passes if no crashes occur from concurrent access
    }
}
