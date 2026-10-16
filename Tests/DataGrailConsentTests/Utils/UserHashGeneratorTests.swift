import XCTest
@testable import DataGrailConsent

/// Tests for user_hash generation (SHA-256 cross-platform recipe)
final class UserHashGeneratorTests: XCTestCase {

    // MARK: - Hash Generation Tests

    func testGeneratesValidSHA256Hash() {
        let hash = UserHashGenerator.generateUserHash(
            customerId: "cust-1",
            consentProjectId: "default",
            deviceIdentifier: "12345678-1234-1234-1234-123456789012"
        )

        // Should be 64-character hex string (SHA-256)
        XCTAssertEqual(hash.count, 64, "SHA-256 hash should be 64 hex characters")
        XCTAssertTrue(hash.allSatisfy { $0.isHexDigit }, "Hash should contain only hex digits")
    }

    func testGeneratesDeterministicHash() {
        let hash1 = UserHashGenerator.generateUserHash(
            customerId: "cust-1",
            consentProjectId: "default",
            deviceIdentifier: "12345678-1234-1234-1234-123456789012"
        )

        let hash2 = UserHashGenerator.generateUserHash(
            customerId: "cust-1",
            consentProjectId: "default",
            deviceIdentifier: "12345678-1234-1234-1234-123456789012"
        )

        XCTAssertEqual(hash1, hash2, "Same inputs should produce same hash")
    }

    func testDifferentInputsProduceDifferentHashes() {
        let hash1 = UserHashGenerator.generateUserHash(
            customerId: "cust-1",
            consentProjectId: "default",
            deviceIdentifier: "12345678-1234-1234-1234-123456789012"
        )

        let hash2 = UserHashGenerator.generateUserHash(
            customerId: "cust-2",
            consentProjectId: "default",
            deviceIdentifier: "12345678-1234-1234-1234-123456789012"
        )

        XCTAssertNotEqual(hash1, hash2, "Different customer_id should produce different hash")
    }

    func testHashMatchesExpectedValueForKnownInput() {
        let hash = UserHashGenerator.generateUserHash(
            customerId: "cust-1",
            consentProjectId: "default",
            deviceIdentifier: "test-device-123"
        )

        // SHA-256("cust-1:default:test-device-123")
        let expectedHash = "66301a6aab1f3c76adb3256743ce3a6b049ae2ff08e4afeb12f94c8761748a69"
        XCTAssertEqual(hash, expectedHash, "Should match known SHA-256 test vector")
    }

    func testAutoDetectsDeviceIdentifier() {
        // When deviceIdentifier is nil, should auto-detect
        let hash = UserHashGenerator.generateUserHash(
            customerId: "cust-1",
            consentProjectId: "default",
            deviceIdentifier: nil
        )

        XCTAssertEqual(hash.count, 64, "Should generate hash with auto-detected device ID")
    }

    func testConsistentHashWithAutoDetectedDevice() {
        // Auto-detected device ID should be stable across calls
        let hash1 = UserHashGenerator.generateUserHash(
            customerId: "cust-1",
            consentProjectId: "default",
            deviceIdentifier: nil
        )

        let hash2 = UserHashGenerator.generateUserHash(
            customerId: "cust-1",
            consentProjectId: "default",
            deviceIdentifier: nil
        )

        XCTAssertEqual(hash1, hash2, "Auto-detected device ID should be stable")
    }

    // MARK: - tvOS-specific Tests

    #if os(tvOS)
        func testTvOSUsesIDFAOrIDFV() {
            // On tvOS, should use IDFA (if available) or IDFV
            let hash = UserHashGenerator.generateUserHash(
                customerId: "cust-1",
                consentProjectId: "default",
                deviceIdentifier: nil
            )

            XCTAssertEqual(hash.count, 64, "Should generate valid hash on tvOS")
        }
    #endif

    // MARK: - iOS-specific Tests

    #if os(iOS)
        func testIOSUsesIDFV() {
            // On iOS, should use IDFV (not IDFA, to avoid ATT prompt)
            let hash = UserHashGenerator.generateUserHash(
                customerId: "cust-1",
                consentProjectId: "default",
                deviceIdentifier: nil
            )

            XCTAssertEqual(hash.count, 64, "Should generate valid hash on iOS")
        }
    #endif
}

extension Character {
    var isHexDigit: Bool {
        ("0"..."9").contains(self) || ("a"..."f").contains(self) || ("A"..."F").contains(self)
    }
}
