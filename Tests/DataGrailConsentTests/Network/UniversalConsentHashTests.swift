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

    // MARK: - projectId is hashed VERBATIM, and the blank-check gates the same value

    /// The cross-SDK contract inserts `projectId` into the hash input VERBATIM — web/Android/React
    /// and every documented backend helper interpolate it raw and normalize ONLY the identifier.
    /// So `validatedUserHash` must both (a) reproduce the golden hash for the golden projectId and
    /// (b) hash a whitespace-carrying projectId byte-for-byte the same as `userHash` does with the
    /// raw value — i.e. it must NOT trim before hashing. Trimming here would validate one string
    /// while hashing another and would split the user from every other SDK's record.
    func testValidatedUserHashHashesProjectIdVerbatim() throws {
        // Golden projectId: validatedUserHash agrees with the golden vector.
        let goldenConfig = UCFixtures.makeConfig(privacyDomain: "x", consentProjectId: goldenProjectId)
        XCTAssertEqual(
            try ConsentService.validatedUserHash(identifier: "user@example.com", config: goldenConfig),
            goldenHash
        )

        // A projectId with incidental trailing whitespace is hashed verbatim — identical to
        // userHash on the raw value, and (guard against a trim-before-hash regression) NOT the
        // golden hash.
        let rawProjectId = "proj_abc123 "
        let wsConfig = UCFixtures.makeConfig(privacyDomain: "x", consentProjectId: rawProjectId)
        let validated = try ConsentService.validatedUserHash(identifier: "user@example.com", config: wsConfig)
        XCTAssertEqual(
            validated,
            ConsentService.userHash(
                dgCustomerId: goldenCustomerId,
                consentProjectId: rawProjectId,
                identifier: "user@example.com"
            ),
            "validatedUserHash must hash the projectId verbatim, not a trimmed copy"
        )
        XCTAssertNotEqual(validated, goldenHash, "a trailing-whitespace projectId is a distinct scope")
    }

    /// An empty (missing) projectId is rejected — the same verbatim value the hash would use.
    func testValidatedUserHashRejectsEmptyProjectId() {
        let config = UCFixtures.makeConfig(privacyDomain: "x", consentProjectId: "")
        XCTAssertThrowsError(
            try ConsentService.validatedUserHash(identifier: "user@example.com", config: config)
        )
    }

    /// A whitespace-only projectId is NOT rejected: the blank-check gates on the raw value the
    /// hash uses, and the cross-SDK contract hashes projectId verbatim. It is a degenerate but
    /// non-empty scope, hashed as-is (byte-identical to `userHash` on the raw value) — the fix
    /// deliberately does not trim it away, which would validate one string and hash another.
    func testValidatedUserHashAcceptsWhitespaceProjectIdVerbatim() throws {
        let raw = "   "
        let config = UCFixtures.makeConfig(privacyDomain: "x", consentProjectId: raw)
        XCTAssertEqual(
            try ConsentService.validatedUserHash(identifier: "user@example.com", config: config),
            ConsentService.userHash(
                dgCustomerId: goldenCustomerId,
                consentProjectId: raw,
                identifier: "user@example.com"
            )
        )
    }
}
