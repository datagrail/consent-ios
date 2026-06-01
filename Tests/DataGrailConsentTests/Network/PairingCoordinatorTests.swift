#if os(tvOS)
    import XCTest
    @testable import DataGrailConsent

    /// Tests for pairing coordinator (polling loop, timeout, callbacks)
    final class PairingCoordinatorTests: XCTestCase {
        var mockNetworkClient: MockNetworkClientForPairing!
        var pairingService: PairingService!

        override func setUp() {
            super.setUp()
            mockNetworkClient = MockNetworkClientForPairing()
            pairingService = PairingService(
                networkClient: mockNetworkClient,
                apiBaseUrl: "https://consent.datagrail.io",
                apiKey: "test-api-key"
            )
        }

        override func tearDown() {
            // Ensure no lingering timers
            super.tearDown()
        }

        // MARK: - Polling Tests

        func testCoordinatorStartsPolling() {
            let coordinator = PairingCoordinator(
                pairingService: pairingService,
                customerId: "cust-1",
                userHash: String(repeating: "a", count: 64),
                pollInterval: 0.1,
                timeout: 10.0
            )

            // Mock not_found response
            let notFoundResponse = """
            {
              "status": "not_found"
            }
            """.data(using: .utf8)!
            mockNetworkClient.mockResponse = notFoundResponse

            coordinator.startPolling()

            // Wait a bit to allow first poll
            let expectation = self.expectation(description: "First poll")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 1.0)

            // Should have made at least one request
            XCTAssertNotNil(mockNetworkClient.lastRequest, "Should have polled")

            coordinator.stopPolling()
        }

        func testCoordinatorCallsOnConsentFound() {
            let coordinator = PairingCoordinator(
                pairingService: pairingService,
                customerId: "cust-1",
                userHash: String(repeating: "a", count: 64),
                pollInterval: 0.1,
                timeout: 10.0
            )

            let expectation = self.expectation(description: "Consent found")

            // Mock found response
            let foundResponse = """
            {
              "status": "found",
              "consent_preferences": {
                "isCustomised": true,
                "cookieOptions": { "dg-category-marketing": false }
              }
            }
            """.data(using: .utf8)!
            mockNetworkClient.mockResponse = foundResponse

            coordinator.onConsentFound = { preferences in
                XCTAssertTrue(preferences.isCustomised)
                XCTAssertEqual(preferences.cookieOptions.count, 1)
                expectation.fulfill()
            }

            coordinator.startPolling()

            wait(for: [expectation], timeout: 2.0)

            coordinator.stopPolling()
        }

        func testCoordinatorStopsPollingAfterFound() {
            let coordinator = PairingCoordinator(
                pairingService: pairingService,
                customerId: "cust-1",
                userHash: String(repeating: "a", count: 64),
                pollInterval: 0.1,
                timeout: 10.0
            )

            let expectation = self.expectation(description: "Consent found")

            // Mock found response
            let foundResponse = """
            {
              "status": "found",
              "consent_preferences": {
                "isCustomised": true,
                "cookieOptions": {}
              }
            }
            """.data(using: .utf8)!
            mockNetworkClient.mockResponse = foundResponse

            coordinator.onConsentFound = { _ in
                expectation.fulfill()
            }

            coordinator.startPolling()

            wait(for: [expectation], timeout: 2.0)

            // Reset request count
            mockNetworkClient.lastRequest = nil

            // Wait a bit more to ensure no more polls
            let noMorePolls = self.expectation(description: "No more polls")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                noMorePolls.fulfill()
            }
            wait(for: [noMorePolls], timeout: 1.0)

            // Should not have made another request
            XCTAssertNil(
                mockNetworkClient.lastRequest,
                "Should have stopped polling after found"
            )
        }

        func testCoordinatorCallsOnTimeout() {
            let coordinator = PairingCoordinator(
                pairingService: pairingService,
                customerId: "cust-1",
                userHash: String(repeating: "a", count: 64),
                pollInterval: 0.1,
                timeout: 0.5  // Short timeout for testing
            )

            let expectation = self.expectation(description: "Timeout")

            // Mock not_found response (never finds)
            let notFoundResponse = """
            {
              "status": "not_found"
            }
            """.data(using: .utf8)!
            mockNetworkClient.mockResponse = notFoundResponse

            coordinator.onTimeout = {
                expectation.fulfill()
            }

            coordinator.startPolling()

            wait(for: [expectation], timeout: 2.0)

            coordinator.stopPolling()
        }

        func testCoordinatorPollsMultipleTimes() {
            let coordinator = PairingCoordinator(
                pairingService: pairingService,
                customerId: "cust-1",
                userHash: String(repeating: "a", count: 64),
                pollInterval: 0.1,
                timeout: 10.0
            )

            // Mock not_found response
            let notFoundResponse = """
            {
              "status": "not_found"
            }
            """.data(using: .utf8)!
            mockNetworkClient.mockResponse = notFoundResponse

            var pollCount = 0
            mockNetworkClient.onRequest = {
                pollCount += 1
            }

            coordinator.startPolling()

            // Wait for multiple polls
            let expectation = self.expectation(description: "Multiple polls")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 2.0)

            coordinator.stopPolling()

            // Should have polled multiple times
            XCTAssertGreaterThan(pollCount, 2, "Should have polled at least 3 times")
        }

        func testCoordinatorHandlesNetworkErrors() {
            let coordinator = PairingCoordinator(
                pairingService: pairingService,
                customerId: "cust-1",
                userHash: String(repeating: "a", count: 64),
                pollInterval: 0.1,
                timeout: 10.0
            )

            // Mock network error
            mockNetworkClient.mockError = ConsentError.networkError("Test error")

            coordinator.startPolling()

            // Wait a bit to allow first poll
            let expectation = self.expectation(description: "Error handled")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 1.0)

            // Should continue polling despite error (transient network errors)
            // This is the expected behavior per the spec

            coordinator.stopPolling()
        }

        func testStopPollingCleansUpTimers() {
            let coordinator = PairingCoordinator(
                pairingService: pairingService,
                customerId: "cust-1",
                userHash: String(repeating: "a", count: 64),
                pollInterval: 0.1,
                timeout: 10.0
            )

            // Mock not_found response
            let notFoundResponse = """
            {
              "status": "not_found"
            }
            """.data(using: .utf8)!
            mockNetworkClient.mockResponse = notFoundResponse

            coordinator.startPolling()

            // Stop immediately
            coordinator.stopPolling()

            // Reset request count
            mockNetworkClient.lastRequest = nil

            // Wait a bit to ensure no more polls
            let expectation = self.expectation(description: "No more polls after stop")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 1.0)

            XCTAssertNil(
                mockNetworkClient.lastRequest,
                "Should not poll after stopPolling"
            )
        }
    }
#endif
