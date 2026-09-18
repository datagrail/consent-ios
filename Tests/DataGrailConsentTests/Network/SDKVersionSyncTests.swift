@testable import DataGrailConsent
import XCTest

/// Guards against ConsentService.sdkVersion drifting from DataGrailConsent.podspec's s.version,
/// since nothing reads the podspec at runtime to keep them in sync automatically.
final class SDKVersionSyncTests: XCTestCase {
    func testSdkVersionMatchesPodspec() throws {
        let podspecUrl = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Network
            .deletingLastPathComponent() // DataGrailConsentTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("DataGrailConsent.podspec")
        let podspec = try String(contentsOf: podspecUrl, encoding: .utf8)

        let regex = try NSRegularExpression(pattern: #"s\.version\s*=\s*'([^']+)'"#)
        let nsPodspec = podspec as NSString
        let match = try XCTUnwrap(
            regex.firstMatch(in: podspec, range: NSRange(location: 0, length: nsPodspec.length)),
            "Couldn't find s.version in DataGrailConsent.podspec"
        )
        let podspecVersion = nsPodspec.substring(with: match.range(at: 1))

        XCTAssertEqual(
            ConsentService.sdkVersion,
            podspecVersion,
            "ConsentService.sdkVersion is out of sync with DataGrailConsent.podspec's s.version"
        )
    }
}
