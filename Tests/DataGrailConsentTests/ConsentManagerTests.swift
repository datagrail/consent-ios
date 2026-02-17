import XCTest

@testable import DataGrailConsent

/// Tests for ConsentManager state management and category detection
final class ConsentManagerTests: XCTestCase {
    var storage: ConsentStorage!
    var mockNetworkClient: MockNetworkClient!
    var configService: ConfigService!
    var consentService: ConsentService!
    var sut: ConsentManager!

    override func setUp() {
        super.setUp()
        storage = ConsentStorage()
        storage.clearAll()
        mockNetworkClient = MockNetworkClient()
        configService = ConfigService(networkClient: mockNetworkClient, storage: storage)
        consentService = ConsentService(
            networkClient: mockNetworkClient,
            storage: storage,
            privacyDomain: "consent.datagrail.io"
        )
        sut = ConsentManager(
            storage: storage,
            configService: configService,
            consentService: consentService
        )
    }

    override func tearDown() {
        storage.clearAll()
        super.tearDown()
    }

    // MARK: - Helper to load test config

    private func loadTestConfig() throws -> ConsentConfig {
        guard let configUrl = Bundle.module.url(forResource: "test-config", withExtension: "json")
        else {
            throw NSError(
                domain: "Test", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "test-config.json not found"]
            )
        }
        let configData = try Data(contentsOf: configUrl)
        let decoder = JSONDecoder()
        return try decoder.decode(ConsentConfig.self, from: configData)
    }

    private func setupManagerWithConfig() {
        guard let configUrl = Bundle.module.url(forResource: "test-config", withExtension: "json"),
              let configData = try? Data(contentsOf: configUrl),
              let testUrl = URL(string: "https://example.com/config.json")
        else {
            return
        }

        let expectation = expectation(description: "Config loaded")
        mockNetworkClient.requestResult = .success(configData)

        sut.loadConfig(from: testUrl) { _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - getUserPreferences Tests

    func testGetUserPreferences_WithNoSavedPreferences_ReturnsNil() {
        // Given - storage is empty

        // When
        let preferences = sut.getUserPreferences()

        // Then
        XCTAssertNil(preferences, "Should return nil when no preferences are saved")
    }

    func testGetUserPreferences_WithSavedPreferences_ReturnsSavedPreferences() throws {
        // Given
        let savedPreferences = ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "dg-category-essential", isEnabled: true),
                CategoryConsent(gtmKey: "dg-category-marketing", isEnabled: false),
            ]
        )
        try storage.savePreferences(savedPreferences)

        // When
        let preferences = sut.getUserPreferences()

        // Then
        guard let unwrappedPreferences = preferences else {
            XCTFail("Preferences should not be nil")
            return
        }
        XCTAssertTrue(unwrappedPreferences.isCustomised)
        XCTAssertEqual(unwrappedPreferences.cookieOptions.count, 2)
        XCTAssertTrue(unwrappedPreferences.isCategoryEnabled("dg-category-essential"))
        XCTAssertFalse(unwrappedPreferences.isCategoryEnabled("dg-category-marketing"))
    }

    // MARK: - getDefaultPreferences Tests

    func testGetDefaultPreferences_WithNoConfig_ReturnsNil() {
        // Given - no config loaded

        // When
        let preferences = sut.getDefaultPreferences()

        // Then
        XCTAssertNil(preferences, "Should return nil when no config is loaded")
    }

    func testGetDefaultPreferences_WithConfig_ReturnsInitialCategories() {
        // Given
        setupManagerWithConfig()

        // When
        let preferences = sut.getDefaultPreferences()

        // Then
        guard let unwrappedPreferences = preferences else {
            XCTFail("Preferences should not be nil")
            return
        }
        XCTAssertFalse(
            unwrappedPreferences.isCustomised, "Default preferences should not be customised"
        )
        XCTAssertEqual(
            unwrappedPreferences.cookieOptions.count,
            5,
            "Should have 5 categories from initialCategories.initial + consent layers"
        )

        // Verify all categories are enabled
        XCTAssertTrue(unwrappedPreferences.isCategoryEnabled("dg-category-essential"))
        XCTAssertTrue(unwrappedPreferences.isCategoryEnabled("dg-category-performance"))
        XCTAssertTrue(unwrappedPreferences.isCategoryEnabled("dg-category-functional"))
        XCTAssertTrue(unwrappedPreferences.isCategoryEnabled("dg-category-marketing"))
        XCTAssertTrue(unwrappedPreferences.isCategoryEnabled("dg-category-mystery-category"))
    }

    // MARK: - getCategories Tests

    func testGetCategories_WithNoConfigAndNoPreferences_ReturnsNil() {
        // Given - no config loaded, no saved preferences

        // When
        let preferences = sut.getCategories()

        // Then
        XCTAssertNil(preferences, "Should return nil when no config is loaded")
    }

    func testGetCategories_WithConfigButNoSavedPreferences_ReturnsDefaultPreferences() {
        // Given
        setupManagerWithConfig()

        // When
        let preferences = sut.getCategories()

        // Then
        guard let unwrappedPreferences = preferences else {
            XCTFail("Preferences should not be nil")
            return
        }
        XCTAssertFalse(
            unwrappedPreferences.isCustomised, "Should return non-customised default preferences"
        )
        XCTAssertEqual(unwrappedPreferences.cookieOptions.count, 5)

        // All categories from initialCategories.initial + consent layers should be enabled
        XCTAssertTrue(unwrappedPreferences.isCategoryEnabled("dg-category-essential"))
        XCTAssertTrue(unwrappedPreferences.isCategoryEnabled("dg-category-performance"))
        XCTAssertTrue(unwrappedPreferences.isCategoryEnabled("dg-category-functional"))
        XCTAssertTrue(unwrappedPreferences.isCategoryEnabled("dg-category-marketing"))
        XCTAssertTrue(unwrappedPreferences.isCategoryEnabled("dg-category-mystery-category"))
    }

    func testGetCategories_WithSavedPreferences_ReturnsSavedPreferences() throws {
        // Given
        setupManagerWithConfig()
        let savedPreferences = ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "dg-category-essential", isEnabled: true),
                CategoryConsent(gtmKey: "dg-category-marketing", isEnabled: false),
                CategoryConsent(gtmKey: "dg-category-performance", isEnabled: false),
                CategoryConsent(gtmKey: "dg-category-functional", isEnabled: true),
            ]
        )
        try storage.savePreferences(savedPreferences)

        // When
        let preferences = sut.getCategories()

        // Then
        guard let unwrappedPreferences = preferences else {
            XCTFail("Preferences should not be nil")
            return
        }
        XCTAssertTrue(
            unwrappedPreferences.isCustomised, "Should return saved customised preferences"
        )
        XCTAssertTrue(unwrappedPreferences.isCategoryEnabled("dg-category-essential"))
        XCTAssertFalse(unwrappedPreferences.isCategoryEnabled("dg-category-marketing"))
        XCTAssertFalse(unwrappedPreferences.isCategoryEnabled("dg-category-performance"))
        XCTAssertTrue(unwrappedPreferences.isCategoryEnabled("dg-category-functional"))
    }

    // MARK: - isCategoryEnabled Tests

    func testIsCategoryEnabled_WithNoConfigOrPreferences_ReturnsFalse() {
        // Given - no config, no preferences

        // When
        let isEnabled = sut.isCategoryEnabled("dg-category-marketing")

        // Then
        XCTAssertFalse(isEnabled, "Should return false when no config or preferences exist")
    }

    func testIsCategoryEnabled_WithConfigButNoSavedPreferences_UsesInitialCategories() {
        // Given
        setupManagerWithConfig()

        // When/Then - Categories in initialCategories.initial should be enabled
        XCTAssertTrue(sut.isCategoryEnabled("dg-category-essential"))
        XCTAssertTrue(sut.isCategoryEnabled("dg-category-marketing"))
        XCTAssertTrue(sut.isCategoryEnabled("dg-category-performance"))
        XCTAssertTrue(sut.isCategoryEnabled("dg-category-functional"))

        // Category not in initial list should be disabled
        XCTAssertFalse(sut.isCategoryEnabled("dg-category-unknown"))
    }

    func testIsCategoryEnabled_WithSavedPreferences_UsesSavedValues() throws {
        // Given
        setupManagerWithConfig()
        let savedPreferences = ConsentPreferences(
            isCustomised: true,
            cookieOptions: [
                CategoryConsent(gtmKey: "dg-category-essential", isEnabled: true),
                CategoryConsent(gtmKey: "dg-category-marketing", isEnabled: false),
            ]
        )
        try storage.savePreferences(savedPreferences)

        // When/Then
        XCTAssertTrue(sut.isCategoryEnabled("dg-category-essential"))
        XCTAssertFalse(sut.isCategoryEnabled("dg-category-marketing"))
    }

    // MARK: - Essential Categories Tests

    func testGetEssentialCategories_WithNoConfig_ReturnsEmpty() {
        // Given - no config loaded

        // When
        let essentialCategories = sut.getEssentialCategories()

        // Then
        XCTAssertTrue(essentialCategories.isEmpty)
    }

    func testGetEssentialCategories_WithConfig_ReturnsAlwaysOnCategories() {
        // Given
        setupManagerWithConfig()

        // When
        let essentialCategories = sut.getEssentialCategories()

        // Then - The test config has dg-category-essential marked as alwaysOn: true
        XCTAssertFalse(essentialCategories.isEmpty, "Should have at least one essential category")
        XCTAssertTrue(
            essentialCategories.contains("dg-category-essential"),
            "Should contain dg-category-essential which is marked as always_on: true in test config"
        )
    }

    func testGetEssentialCategories_DoesNotIncludeNonEssentialCategories() {
        // Given
        setupManagerWithConfig()

        // When
        let essentialCategories = sut.getEssentialCategories()

        // Then - Marketing is not essential
        XCTAssertFalse(
            essentialCategories.contains("dg-category-marketing"),
            "Should not contain dg-category-marketing which is not always_on"
        )
        XCTAssertFalse(
            essentialCategories.contains("dg-category-mystery-category"),
            "Should not contain dg-category-mystery-category which is not always_on"
        )
    }

    // MARK: - getAllCategoryKeys Tests (tested via getDefaultPreferences)

    func testGetDefaultPreferences_IncludesCategoriesFromConsentLayers() {
        // Given
        setupManagerWithConfig()

        // When
        let preferences = sut.getDefaultPreferences()

        // Then - Should include dg-category-mystery-category from consent layers
        // even though it might not be in initialCategories.initial
        guard let unwrappedPreferences = preferences else {
            XCTFail("Preferences should not be nil")
            return
        }
        XCTAssertTrue(
            unwrappedPreferences.isCategoryEnabled("dg-category-mystery-category"),
            "Should include categories from consent layers"
        )
    }

    // MARK: - shouldDisplayBanner Tests

    func testShouldDisplayBanner_WithNoConfig_ReturnsFalse() {
        // Given - no config loaded

        // When
        let shouldDisplay = sut.shouldDisplayBanner()

        // Then
        XCTAssertFalse(shouldDisplay)
    }

    func testShouldDisplayBanner_WithShowBannerFalse_ReturnsFalse() {
        // Given - test config has showBanner: false
        setupManagerWithConfig()

        // When
        let shouldDisplay = sut.shouldDisplayBanner()

        // Then
        XCTAssertFalse(shouldDisplay, "Should return false when showBanner is false in config")
    }

    func testShouldDisplayBanner_WithSavedPreferences_ReturnsFalse() throws {
        // Given
        setupManagerWithConfig()
        let savedPreferences = ConsentPreferences(
            isCustomised: true,
            cookieOptions: [CategoryConsent(gtmKey: "dg-category-essential", isEnabled: true)]
        )
        try storage.savePreferences(savedPreferences)

        // When
        let shouldDisplay = sut.shouldDisplayBanner()

        // Then
        XCTAssertFalse(shouldDisplay, "Should return false when preferences are saved")
    }

    // MARK: - hasUserConsent Tests

    func testHasUserConsent_WithNoSavedPreferences_ReturnsFalse() {
        // Given - no saved preferences

        // When
        let hasConsent = sut.hasUserConsent()

        // Then
        XCTAssertFalse(hasConsent)
    }

    func testHasUserConsent_WithSavedPreferences_ReturnsTrue() throws {
        // Given
        let preferences = ConsentPreferences(
            isCustomised: true,
            cookieOptions: [CategoryConsent(gtmKey: "dg-category-essential", isEnabled: true)]
        )
        try storage.savePreferences(preferences)

        // When
        let hasConsent = sut.hasUserConsent()

        // Then
        XCTAssertTrue(hasConsent)
    }

    // MARK: - Reset Tests

    func testReset_ClearsPreferences() throws {
        // Given
        setupManagerWithConfig()
        let preferences = ConsentPreferences(
            isCustomised: true,
            cookieOptions: [CategoryConsent(gtmKey: "dg-category-essential", isEnabled: true)]
        )
        try storage.savePreferences(preferences)
        XCTAssertNotNil(sut.getUserPreferences())

        // When
        sut.reset()

        // Then
        XCTAssertNil(sut.getUserPreferences())
        XCTAssertNil(sut.config)
    }
}
