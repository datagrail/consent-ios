import XCTest
@testable import DataGrailConsent

/// The whole point of modeling ATT as four states rather than a boolean is that only two
/// of them are opt-outs. These tests pin that mapping, because collapsing it is the exact
/// mistake that either silently opts out every user who has not seen the prompt yet, or
/// grants marketing consent to everyone who tapped "Allow".
final class TrackingSignalTests: XCTestCase {
    func testDeniedAndRestrictedSuppress() {
        XCTAssertTrue(TrackingSignal.denied.suppressesNonEssential)
        // Restricted means the device forbids tracking (MDM, parental controls). The user
        // cannot be tracked, so it is as much an opt-out as an explicit refusal.
        XCTAssertTrue(TrackingSignal.restricted.suppressesNonEssential)
    }

    func testNotDeterminedDoesNotSuppress() {
        // An unanswered prompt is not a refusal. Treating it as one would opt out every
        // user before they were ever asked.
        XCTAssertFalse(TrackingSignal.notDetermined.suppressesNonEssential)
    }

    func testAuthorizedDoesNotSuppress() {
        XCTAssertFalse(TrackingSignal.authorized.suppressesNonEssential)
    }

    /// A signal may only turn categories OFF. ATT `authorized` is permission to track,
    /// not consent to marketing — if this ever starts enabling categories, a user who
    /// opted out of marketing on the web would be silently opted back in by tapping
    /// "Allow" on an unrelated iOS prompt.
    func testNoSignalStateEnablesADisabledCategory() {
        let allOff: [String: Bool] = [
            "dg-category-essential": true,
            "dg-category-marketing": false,
            "dg-category-performance": false,
        ]

        for signal in [TrackingSignal.authorized, .notDetermined, .denied, .restricted] {
            let effective = ConsentService.reconcile(
                cookieOptions: allOff,
                suppress: signal.suppressesNonEssential,
                essentialCategoryKeys: ["dg-category-essential"]
            )

            XCTAssertEqual(
                effective["dg-category-marketing"], false,
                "\(signal.rawValue) must not enable a category the user turned off"
            )
            XCTAssertEqual(
                effective["dg-category-performance"], false,
                "\(signal.rawValue) must not enable a category the user turned off"
            )
        }
    }

    /// Reading the signal must never prompt and must never crash, including on OS
    /// versions predating ATT — the SDK still supports iOS 13, where the framework's
    /// symbols are unavailable at runtime.
    func testReaderReturnsAKnownStateWithoutPrompting() {
        let signal = TrackingSignalReader.current()
        XCTAssertTrue(
            [.notDetermined, .restricted, .denied, .authorized].contains(signal),
            "Reader returned an unmapped state: \(signal.rawValue)"
        )
    }
}
