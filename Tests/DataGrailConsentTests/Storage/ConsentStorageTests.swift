@testable import DataGrailConsent
import XCTest

// swiftlint:disable force_unwrapping
final class ConsentStorageTests: XCTestCase {
    var storage: ConsentStorage!
    var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // Use a unique suite name for tests to avoid conflicts
        userDefaults = UserDefaults(suiteName: "test.datagrail.consent.\(UUID().uuidString)")!
        storage = ConsentStorage(userDefaults: userDefaults)
    }

    override func tearDown() {
        storage.clearAll()
        super.tearDown()
    }

    func testSaveAndLoadPreferences() throws {
        let prefs = ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "category_marketing", isEnabled: true),
            ]
        )

        try storage.savePreferences(prefs)

        let loaded = storage.loadPreferences()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded, prefs)
    }

    func testLoadPreferencesWhenNoneExist() {
        let loaded = storage.loadPreferences()
        XCTAssertNil(loaded)
    }

    func testGetOrCreateUniqueId() {
        let id1 = storage.getOrCreateUniqueId()
        XCTAssertFalse(id1.isEmpty)

        // Should return the same ID on subsequent calls
        let id2 = storage.getOrCreateUniqueId()
        XCTAssertEqual(id1, id2)
    }

    func testSaveAndLoadConfigVersion() {
        let version = "1.2.3"
        storage.saveConfigVersion(version)

        let loaded = storage.loadConfigVersion()
        XCTAssertEqual(loaded, version)
    }

    func testClearAll() throws {
        // Save various data
        let prefs = ConsentPreferences(isCustomised: true, cookieOptions: [])
        try storage.savePreferences(prefs)
        storage.saveConfigVersion("1.0.0")
        _ = storage.getOrCreateUniqueId()

        // Clear all
        storage.clearAll()

        // Verify all cleared
        XCTAssertNil(storage.loadPreferences())
        XCTAssertNil(storage.loadConfigVersion())

        // New unique ID should be generated
        let newId = storage.getOrCreateUniqueId()
        XCTAssertFalse(newId.isEmpty)
    }
}
