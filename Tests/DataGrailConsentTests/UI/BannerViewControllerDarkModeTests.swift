#if canImport(UIKit)
    import XCTest

    @testable import DataGrailConsent

    /// Tests for dark mode support in BannerViewController
    final class BannerViewControllerDarkModeTests: XCTestCase {
        // MARK: - Modal Style Dark Mode Tests

        func testModalStyle_ContainerUsesSystemBackground() {
            let config = BannerAccessibilityTestHelpers.createTestConfig()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            // Find container view
            let containerView = BannerAccessibilityTestHelpers.findView(in: vc.view) {
                $0.accessibilityLabel == "Consent Banner"
            }

            XCTAssertNotNil(containerView, "Container view should exist")
            XCTAssertEqual(
                containerView?.backgroundColor,
                .systemBackground,
                "Container should use .systemBackground for dark mode support"
            )
        }

        func testModalStyle_BackdropUsesTranslucentBlack() {
            let config = BannerAccessibilityTestHelpers.createTestConfig()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            // The view's background should be translucent black (backdrop)
            let expectedColor = UIColor.black.withAlphaComponent(0.5)
            XCTAssertEqual(
                vc.view.backgroundColor,
                expectedColor,
                "Modal backdrop should use translucent black"
            )
        }

        // MARK: - Full Screen Style Dark Mode Tests

        func testFullScreenStyle_ViewUsesSystemBackground() {
            let config = BannerAccessibilityTestHelpers.createTestConfig()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .fullScreen,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            XCTAssertEqual(
                vc.view.backgroundColor,
                .systemBackground,
                "Full screen view should use .systemBackground for dark mode support"
            )
        }

        func testFullScreenStyle_ContainerUsesSystemBackground() {
            let config = BannerAccessibilityTestHelpers.createTestConfig()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .fullScreen,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let containerView = BannerAccessibilityTestHelpers.findView(in: vc.view) {
                $0.accessibilityLabel == "Consent Banner"
            }

            XCTAssertNotNil(containerView, "Container view should exist")
            XCTAssertEqual(
                containerView?.backgroundColor,
                .systemBackground,
                "Full screen container should use .systemBackground for dark mode support"
            )
        }

        // MARK: - Close Button Dark Mode Tests

        func testCloseButton_UsesSecondaryLabelColor() {
            let config = BannerAccessibilityTestHelpers.createTestConfig()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let closeButton = BannerAccessibilityTestHelpers.findButton(
                in: vc.view,
                withAccessibilityLabel: "Close consent banner"
            )

            XCTAssertNotNil(closeButton, "Close button should exist")
            XCTAssertEqual(
                closeButton?.tintColor,
                .secondaryLabel,
                "Close button should use .secondaryLabel for dark mode support"
            )
        }

        // MARK: - Text Element Dark Mode Tests

        func testTextElement_UsesLabelColor() {
            let config = BannerAccessibilityTestHelpers.createTestConfig()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let textLabel = BannerAccessibilityTestHelpers.findLabel(
                in: vc.view,
                withText: "We value your privacy"
            )

            XCTAssertNotNil(textLabel, "Text label should exist")
            XCTAssertEqual(
                textLabel?.textColor,
                .label,
                "Text labels should use .label for dark mode support"
            )
        }

        // MARK: - Category Element Dark Mode Tests

        func testCategoryLabel_UsesLabelColor() {
            let config = BannerAccessibilityTestHelpers.createConfigWithCategories()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let categoryLabel = BannerAccessibilityTestHelpers.findLabel(
                in: vc.view,
                withText: "Marketing"
            )

            XCTAssertNotNil(categoryLabel, "Category label should exist")
            XCTAssertEqual(
                categoryLabel?.textColor,
                .label,
                "Category labels should use .label for dark mode support"
            )
        }

        // MARK: - Tracking Details Dark Mode Tests

        func testTrackingDetailsText_UsesSecondaryLabelColor() {
            let config = BannerAccessibilityTestHelpers.createConfigWithTrackingDetails()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let detailsLabel = BannerAccessibilityTestHelpers.findLabel(
                in: vc.view,
                withText: "Tracking details text"
            )

            XCTAssertNotNil(detailsLabel, "Tracking details label should exist")
            XCTAssertEqual(
                detailsLabel?.textColor,
                .secondaryLabel,
                "Tracking details should use .secondaryLabel for dark mode support"
            )
        }

        // MARK: - Trait Collection Tests

        func testColorsAdaptToDarkMode() {
            let config = BannerAccessibilityTestHelpers.createTestConfig()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            // Get colors in light mode
            let lightTraits = UITraitCollection(userInterfaceStyle: .light)
            let lightBackground = UIColor.systemBackground.resolvedColor(
                with: lightTraits
            )

            // Get colors in dark mode
            let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
            let darkBackground = UIColor.systemBackground.resolvedColor(
                with: darkTraits
            )

            // Verify that systemBackground produces different colors in light vs dark
            XCTAssertNotEqual(
                lightBackground,
                darkBackground,
                "systemBackground should produce different colors in light and dark modes"
            )
        }

        func testLabelColorAdaptsToDarkMode() {
            let config = BannerAccessibilityTestHelpers.createTestConfig()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            // Get colors in light mode
            let lightTraits = UITraitCollection(userInterfaceStyle: .light)
            let lightLabel = UIColor.label.resolvedColor(with: lightTraits)

            // Get colors in dark mode
            let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
            let darkLabel = UIColor.label.resolvedColor(with: darkTraits)

            // Verify that .label produces different colors in light vs dark
            XCTAssertNotEqual(
                lightLabel,
                darkLabel,
                ".label should produce different colors in light and dark modes"
            )
        }

        func testSecondaryLabelColorAdaptsToDarkMode() {
            let config = BannerAccessibilityTestHelpers.createTestConfig()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            // Get colors in light mode
            let lightTraits = UITraitCollection(userInterfaceStyle: .light)
            let lightSecondary = UIColor.secondaryLabel.resolvedColor(with: lightTraits)

            // Get colors in dark mode
            let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
            let darkSecondary = UIColor.secondaryLabel.resolvedColor(with: darkTraits)

            // Verify that .secondaryLabel produces different colors in light vs dark
            XCTAssertNotEqual(
                lightSecondary,
                darkSecondary,
                ".secondaryLabel should produce different colors in light and dark modes"
            )
        }

        // MARK: - Integration Tests

        func testAllSemanticColorsUsed() {
            let config = BannerAccessibilityTestHelpers.createConfigWithCategories()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            // Verify container uses semantic color
            let containerView = BannerAccessibilityTestHelpers.findView(in: vc.view) {
                $0.accessibilityLabel == "Consent Banner"
            }
            XCTAssertEqual(containerView?.backgroundColor, .systemBackground)

            // Verify close button uses semantic color
            let closeButton = BannerAccessibilityTestHelpers.findButton(
                in: vc.view,
                withAccessibilityLabel: "Close consent banner"
            )
            XCTAssertEqual(closeButton?.tintColor, .secondaryLabel)

            // Verify category label uses semantic color
            let categoryLabel = BannerAccessibilityTestHelpers.findLabel(
                in: vc.view,
                withText: "Marketing"
            )
            XCTAssertEqual(categoryLabel?.textColor, .label)
        }

        func testNonSemanticColorsNotUsed() {
            let config = BannerAccessibilityTestHelpers.createConfigWithCategories()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            // Verify no views use hardcoded .white for background
            let containerView = BannerAccessibilityTestHelpers.findView(in: vc.view) {
                $0.accessibilityLabel == "Consent Banner"
            }
            XCTAssertNotEqual(
                containerView?.backgroundColor,
                .white,
                "Container should not use hardcoded .white"
            )

            // Verify no labels use hardcoded .darkGray
            let categoryLabel = BannerAccessibilityTestHelpers.findLabel(
                in: vc.view,
                withText: "Marketing"
            )
            XCTAssertNotEqual(
                categoryLabel?.textColor,
                .darkGray,
                "Labels should not use hardcoded .darkGray"
            )

            // Verify close button doesn't use hardcoded .gray
            let closeButton = BannerAccessibilityTestHelpers.findButton(
                in: vc.view,
                withAccessibilityLabel: "Close consent banner"
            )
            XCTAssertNotEqual(
                closeButton?.tintColor,
                .gray,
                "Close button should not use hardcoded .gray"
            )
        }
    }
#endif
