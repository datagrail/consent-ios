@_spi(Diagnostics) @testable import DataGrailConsent
import XCTest

final class DiagnosticsSPITests: XCTestCase {
    func testSDKVersionMatchesConsentService() {
        XCTAssertEqual(DataGrailConsent.sdkVersion, ConsentService.sdkVersion)
    }

    func testSchemaVersionIsV1() {
        XCTAssertEqual(DataGrailConsent.schemaVersion, "v1")
    }
}
