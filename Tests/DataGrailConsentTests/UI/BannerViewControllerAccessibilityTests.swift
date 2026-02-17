#if canImport(UIKit)
    import XCTest

    @testable import DataGrailConsent

    // MARK: - Test Helpers

    /// Shared test utilities for BannerViewController accessibility tests
    enum BannerAccessibilityTestHelpers {
        static func createTestConfig() -> ConsentConfig {
            ConsentConfig(
                version: "1.0",
                dgCustomerId: "test-customer",
                privacyDomain: "test.com",
                consentMode: "optin",
                showBanner: true,
                initialCategories: InitialCategories(initial: []),
                layout: ConsentLayout(
                    firstLayerId: "layer1",
                    consentLayers: [
                        "layer1": ConsentLayer(elements: [
                            ConsentLayerElement(
                                type: "text",
                                id: "text1",
                                translations: [
                                    "en": ElementTranslation(value: "We value your privacy"),
                                ]
                            ),
                        ]),
                    ]
                )
            )
        }

        static func createConfigWithButton(action: ButtonAction, text: String) -> ConsentConfig {
            ConsentConfig(
                version: "1.0",
                dgCustomerId: "test-customer",
                privacyDomain: "test.com",
                consentMode: "optin",
                showBanner: true,
                initialCategories: InitialCategories(initial: []),
                layout: ConsentLayout(
                    firstLayerId: "layer1",
                    consentLayers: [
                        "layer1": ConsentLayer(elements: [
                            ConsentLayerElement(
                                type: "button",
                                id: "btn1",
                                buttonAction: action,
                                translations: ["en": ElementTranslation(text: text)]
                            ),
                        ]),
                    ]
                )
            )
        }

        static func createConfigWithCategories() -> ConsentConfig {
            ConsentConfig(
                version: "1.0",
                dgCustomerId: "test-customer",
                privacyDomain: "test.com",
                consentMode: "optin",
                showBanner: true,
                initialCategories: InitialCategories(initial: [
                    "category_essential", "category_marketing",
                ]),
                layout: ConsentLayout(
                    firstLayerId: "layer1",
                    consentLayers: [
                        "layer1": ConsentLayer(elements: [
                            ConsentLayerElement(
                                type: "category",
                                id: "categories",
                                consentLayerCategories: [
                                    ConsentLayerCategory(
                                        id: "essential",
                                        gtmKey: "category_essential",
                                        primitive: "essential",
                                        alwaysOn: true,
                                        translations: ["en": CategoryTranslation(name: "Essential")]
                                    ),
                                    ConsentLayerCategory(
                                        id: "marketing",
                                        gtmKey: "category_marketing",
                                        primitive: "marketing",
                                        alwaysOn: false,
                                        translations: ["en": CategoryTranslation(name: "Marketing")]
                                    ),
                                ]
                            ),
                        ]),
                    ]
                )
            )
        }

        static func createConfigWithLink() -> ConsentConfig {
            ConsentConfig(
                version: "1.0",
                dgCustomerId: "test-customer",
                privacyDomain: "test.com",
                consentMode: "optin",
                showBanner: true,
                initialCategories: InitialCategories(initial: []),
                layout: ConsentLayout(
                    firstLayerId: "layer1",
                    consentLayers: [
                        "layer1": ConsentLayer(elements: [
                            ConsentLayerElement(
                                type: "link",
                                id: "link1",
                                translations: [
                                    "en": ElementTranslation(
                                        text: "Privacy Policy",
                                        url: "https://example.com/privacy"
                                    ),
                                ]
                            ),
                        ]),
                    ]
                )
            )
        }

        static func findView(in view: UIView, matching predicate: (UIView) -> Bool) -> UIView? {
            if predicate(view) {
                return view
            }
            for subview in view.subviews {
                if let found = findView(in: subview, matching: predicate) {
                    return found
                }
            }
            return nil
        }

        static func findButton(in view: UIView, withAccessibilityLabel label: String) -> UIButton? {
            findView(in: view) { view in
                guard let button = view as? UIButton else { return false }
                return button.accessibilityLabel == label
            } as? UIButton
        }

        static func findButton(in view: UIView, withTitle title: String) -> UIButton? {
            findView(in: view) { view in
                guard let button = view as? UIButton else { return false }
                return button.title(for: .normal) == title
            } as? UIButton
        }

        static func findSwitch(in view: UIView, withAccessibilityIdentifier identifier: String)
            -> UISwitch?
        {
            findView(in: view) { view in
                guard let toggle = view as? UISwitch else { return false }
                return toggle.accessibilityIdentifier == identifier
            } as? UISwitch
        }

        static func findLabel(in view: UIView, withText text: String) -> UILabel? {
            findView(in: view) { view in
                guard let label = view as? UILabel else { return false }
                return label.text == text
            } as? UILabel
        }
    }

    // MARK: - Container Accessibility Tests

    /// Tests for container view accessibility
    final class BannerContainerAccessibilityTests: XCTestCase {
        func testContainerView_HasAccessibilityLabel() {
            let config = BannerAccessibilityTestHelpers.createTestConfig()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let containerView = BannerAccessibilityTestHelpers.findView(in: vc.view) {
                $0.accessibilityLabel == "Consent Banner"
            }
            XCTAssertNotNil(
                containerView, "Container should have 'Consent Banner' accessibility label"
            )
        }

        func testCloseButton_HasAccessibilityProperties() {
            let config = BannerAccessibilityTestHelpers.createTestConfig()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let closeButton = BannerAccessibilityTestHelpers.findButton(
                in: vc.view, withAccessibilityLabel: "Close consent banner"
            )
            XCTAssertNotNil(closeButton, "Close button should have accessibility label")
            XCTAssertEqual(closeButton?.accessibilityHint, "Dismiss without saving preferences")
            XCTAssertTrue(closeButton?.accessibilityTraits.contains(.button) ?? false)
        }
    }

    // MARK: - Button Accessibility Tests

    /// Tests for button element accessibility hints
    final class BannerButtonAccessibilityTests: XCTestCase {
        func testAcceptAllButton_HasAccessibilityHint() {
            let config = BannerAccessibilityTestHelpers.createConfigWithButton(
                action: .acceptAll, text: "Accept All"
            )
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let button = BannerAccessibilityTestHelpers.findButton(
                in: vc.view, withTitle: "Accept All"
            )
            XCTAssertNotNil(button, "Accept All button should exist")
            XCTAssertEqual(button?.accessibilityHint, "Accept all consent categories")
        }

        func testRejectAllButton_HasAccessibilityHint() {
            let config = BannerAccessibilityTestHelpers.createConfigWithButton(
                action: .rejectAll, text: "Reject All"
            )
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let button = BannerAccessibilityTestHelpers.findButton(
                in: vc.view, withTitle: "Reject All"
            )
            XCTAssertNotNil(button, "Reject All button should exist")
            XCTAssertEqual(button?.accessibilityHint, "Reject all non-essential categories")
        }

        func testCustomButton_HasAccessibilityHint() {
            let config = BannerAccessibilityTestHelpers.createConfigWithButton(
                action: .custom, text: "Save Preferences"
            )
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let button = BannerAccessibilityTestHelpers.findButton(
                in: vc.view, withTitle: "Save Preferences"
            )
            XCTAssertNotNil(button, "Save Preferences button should exist")
            XCTAssertEqual(button?.accessibilityHint, "Save your consent preferences")
        }
    }

    // MARK: - Category Toggle Accessibility Tests

    /// Tests for category toggle accessibility
    final class BannerCategoryAccessibilityTests: XCTestCase {
        func testCategoryToggle_HasAccessibilityLabel() {
            let config = BannerAccessibilityTestHelpers.createConfigWithCategories()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let toggle = BannerAccessibilityTestHelpers.findSwitch(
                in: vc.view, withAccessibilityIdentifier: "category_marketing"
            )
            XCTAssertNotNil(toggle, "Marketing toggle should exist")
            XCTAssertEqual(toggle?.accessibilityLabel, "Marketing consent")
        }

        func testCategoryToggle_HasAccessibilityValue() {
            let config = BannerAccessibilityTestHelpers.createConfigWithCategories()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let toggle = BannerAccessibilityTestHelpers.findSwitch(
                in: vc.view, withAccessibilityIdentifier: "category_marketing"
            )
            XCTAssertNotNil(toggle, "Marketing toggle should exist")
            XCTAssertTrue(
                toggle?.accessibilityValue == "Enabled" || toggle?.accessibilityValue == "Disabled",
                "Toggle should have Enabled/Disabled as accessibility value"
            )
        }

        func testEssentialCategoryToggle_HasAlwaysEnabledHint() {
            let config = BannerAccessibilityTestHelpers.createConfigWithCategories()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let toggle = BannerAccessibilityTestHelpers.findSwitch(
                in: vc.view, withAccessibilityIdentifier: "category_essential"
            )
            XCTAssertNotNil(toggle, "Essential toggle should exist")
            XCTAssertEqual(toggle?.accessibilityHint, "Always enabled")
        }

        func testNonEssentialCategoryToggle_HasToggleHint() {
            let config = BannerAccessibilityTestHelpers.createConfigWithCategories()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let toggle = BannerAccessibilityTestHelpers.findSwitch(
                in: vc.view, withAccessibilityIdentifier: "category_marketing"
            )
            XCTAssertNotNil(toggle, "Marketing toggle should exist")
            XCTAssertEqual(toggle?.accessibilityHint, "Double tap to toggle")
        }
    }

    // MARK: - Text and Link Accessibility Tests

    /// Tests for text and link element accessibility
    final class BannerTextLinkAccessibilityTests: XCTestCase {
        func testTextElement_HasAccessibilityLabel() {
            let config = BannerAccessibilityTestHelpers.createTestConfig()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let textLabel = BannerAccessibilityTestHelpers.findLabel(
                in: vc.view, withText: "We value your privacy"
            )
            XCTAssertNotNil(textLabel, "Text element should exist")
            XCTAssertEqual(textLabel?.accessibilityLabel, "We value your privacy")
            XCTAssertTrue(textLabel?.accessibilityTraits.contains(.staticText) ?? false)
        }

        func testLinkElement_HasLinkTraits() {
            let config = BannerAccessibilityTestHelpers.createConfigWithLink()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let linkButton = BannerAccessibilityTestHelpers.findButton(
                in: vc.view, withTitle: "Privacy Policy"
            )
            XCTAssertNotNil(linkButton, "Link button should exist")
            XCTAssertTrue(linkButton?.accessibilityTraits.contains(.link) ?? false)
            XCTAssertEqual(linkButton?.accessibilityHint, "Opens Privacy Policy in browser")
        }
    }
#endif
