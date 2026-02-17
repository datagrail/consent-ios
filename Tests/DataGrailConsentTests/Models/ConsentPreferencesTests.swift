@testable import DataGrailConsent
import XCTest

final class ConsentPreferencesTests: XCTestCase {
    func testPreferencesInitialization() {
        let prefs = ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "category_marketing", isEnabled: true),
                CategoryConsent(gtmKey: "category_analytics", isEnabled: false),
            ]
        )

        XCTAssertTrue(prefs.isCustomised)
        XCTAssertEqual(prefs.cookieOptions.count, 2)
    }

    func testIsCategoryEnabled() {
        let prefs = ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "category_marketing", isEnabled: true),
                CategoryConsent(gtmKey: "category_analytics", isEnabled: false),
            ]
        )

        XCTAssertTrue(prefs.isCategoryEnabled("category_marketing"))
        XCTAssertFalse(prefs.isCategoryEnabled("category_analytics"))
        XCTAssertFalse(prefs.isCategoryEnabled("category_nonexistent"))
    }

    func testCodable() throws {
        let original = ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "category_marketing", isEnabled: true),
            ]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ConsentPreferences.self, from: data)

        XCTAssertEqual(original, decoded)
    }
}
