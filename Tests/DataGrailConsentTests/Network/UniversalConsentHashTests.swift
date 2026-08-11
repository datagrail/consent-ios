@testable import DataGrailConsent
import XCTest

/// Hashing and identifier-normalization tests for Universal Consent (TRUST-1843).
///
/// Split out from `UniversalConsentTests` (which covers GPC reconciliation and the
/// signed POST) because these exercise pure static functions and need none of that
/// suite's mock network/storage fixtures.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class UniversalConsentHashTests: XCTestCase {
    private let goldenCustomerId = "ac46d8ad-a67a-431f-a5d5-9e3eb922dae7"
    private let goldenProjectId = "proj_abc123"
    private let goldenHash = "1fee132c298d615098190e3e75f9c7e05db20d6cff6398f686fcebc67d1d87a4"

    // MARK: - Golden Hash Vector (must be identical across all SDKs)

    func testUserHashGoldenVector() {
        let hash = ConsentService.userHash(
            dgCustomerId: goldenCustomerId,
            consentProjectId: goldenProjectId,
            identifier: "user@example.com"
        )
        XCTAssertEqual(hash, goldenHash)
        XCTAssertEqual(hash.count, 64)
        XCTAssertEqual(hash, hash.lowercased())
    }

    // The golden identifier above is ALREADY normalized, so it reproduces the vector
    // whether or not normalization runs. These are the cases that fail when a
    // normalization step is missing — keep them in lockstep with the web and Android SDKs.
    func testUserHashNormalizesMessyIdentifiersToGoldenVector() {
        let messy = [
            "  User@Example.com  ",
            "User@Example.COM",
            "\tuser@example.com\n",
        ]

        for identifier in messy {
            XCTAssertEqual(
                ConsentService.userHash(
                    dgCustomerId: goldenCustomerId,
                    consentProjectId: goldenProjectId,
                    identifier: identifier
                ),
                goldenHash,
                "normalization must map <\(identifier)> onto the golden hash"
            )
        }
    }

    // MARK: - Normalization contract (NFC → trim → lowercase)

    func testNormalizeUserIdentifierAppliesNFCThenTrimThenLowercase() {
        XCTAssertEqual(
            ConsentService.normalizeUserIdentifier("  User@Example.com  "),
            "user@example.com"
        )
    }

    func testNormalizeUserIdentifierComposesDecomposedUnicode() {
        // "e" + combining acute (U+0301) vs the precomposed "é" (U+00E9): distinct byte
        // sequences for the same name, which NFC must reconcile. Written as escapes so
        // an editor cannot silently normalize the source and make this vacuous.
        let decomposed = "jos\u{0065}\u{0301}@example.com"
        let precomposed = "jos\u{00e9}@example.com"

        XCTAssertNotEqual(Array(decomposed.unicodeScalars), Array(precomposed.unicodeScalars))
        XCTAssertEqual(
            ConsentService.normalizeUserIdentifier(decomposed),
            ConsentService.normalizeUserIdentifier(precomposed)
        )
    }

    func testNormalizeUserIdentifierIsIdempotent() {
        let once = ConsentService.normalizeUserIdentifier("  User@Example.com  ")
        XCTAssertEqual(ConsentService.normalizeUserIdentifier(once), once)
    }
}
