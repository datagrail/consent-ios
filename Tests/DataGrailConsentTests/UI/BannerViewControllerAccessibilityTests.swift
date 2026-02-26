#if canImport(UIKit)
    import XCTest

    @testable import DataGrailConsent

    // MARK: - Test Helpers

    // swiftlint:disable type_body_length
    /// Shared test utilities for BannerViewController accessibility tests
    enum BannerAccessibilityTestHelpers {
        // swiftlint:disable:next function_body_length
        static func createTestConfig() -> ConsentConfig {
            let element = ConsentLayerElement(
                id: "text1",
                order: 1,
                type: "text",
                style: nil,
                buttonAction: nil,
                targetConsentLayer: nil,
                categories: nil,
                links: nil,
                consentLayerCategories: nil,
                showTrackingDetailsLink: nil,
                consentLayerCategoriesConfigId: nil,
                trackingDetailsLinkTranslations: nil,
                showIcon: nil,
                consentLayerBrowserSignalNoticeConfigId: nil,
                browserSignalNoticeTranslations: nil,
                showTrackingServices: nil,
                showCookies: nil,
                showIcons: nil,
                groupByVendor: nil,
                translations: [
                    "en": ElementTranslation(
                        id: nil,
                        locale: "en",
                        value: "We value your privacy",
                        text: nil,
                        url: nil
                    ),
                ]
            )

            let layer = ConsentLayer(
                id: "layer1",
                name: "First Layer",
                theme: "neutral",
                position: "bottom",
                showCloseButton: true,
                bannerApiId: "first",
                elements: [element]
            )

            let layout = Layout(
                id: "layout1",
                name: "Test Layout",
                description: nil,
                status: "published",
                defaultLayout: true,
                collapsedOnMobile: false,
                firstLayerId: "layer1",
                gpcDntLayerId: nil,
                consentLayers: ["layer1": layer]
            )

            return ConsentConfig(
                version: "1.0",
                consentContainerVersionId: "container1",
                dgCustomerId: "test-customer",
                publishDate: 0,
                dch: "categorize",
                dc: "dg-category-essential",
                privacyDomain: "test.com",
                plugins: Plugins(
                    scriptControl: false,
                    allCookieSubdomains: false,
                    cookieBlocking: false,
                    localStorageBlocking: false,
                    syncOTConsent: false
                ),
                testMode: false,
                ignoreDoNotTrack: false,
                trackingDetailsUrl: "https://example.com/tracking",
                consentMode: "optin",
                showBanner: true,
                consentPolicy: ConsentPolicy(name: "Test", default: true),
                gppUsNat: false,
                initialCategories: InitialCategories(
                    respectGpc: false,
                    respectDnt: false,
                    respectOptout: false,
                    initial: [],
                    gpc: [],
                    optout: []
                ),
                layout: layout
            )
        }

        // swiftlint:disable:next function_body_length
        static func createConfigWithButton(action: String, text: String) -> ConsentConfig {
            let element = ConsentLayerElement(
                id: "btn1",
                order: 1,
                type: "button",
                style: nil,
                buttonAction: action,
                targetConsentLayer: nil,
                categories: nil,
                links: nil,
                consentLayerCategories: nil,
                showTrackingDetailsLink: nil,
                consentLayerCategoriesConfigId: nil,
                trackingDetailsLinkTranslations: nil,
                showIcon: nil,
                consentLayerBrowserSignalNoticeConfigId: nil,
                browserSignalNoticeTranslations: nil,
                showTrackingServices: nil,
                showCookies: nil,
                showIcons: nil,
                groupByVendor: nil,
                translations: [
                    "en": ElementTranslation(
                        id: nil,
                        locale: "en",
                        value: nil,
                        text: text,
                        url: nil
                    ),
                ]
            )

            let layer = ConsentLayer(
                id: "layer1",
                name: "First Layer",
                theme: "neutral",
                position: "bottom",
                showCloseButton: true,
                bannerApiId: "first",
                elements: [element]
            )

            let layout = Layout(
                id: "layout1",
                name: "Test Layout",
                description: nil,
                status: "published",
                defaultLayout: true,
                collapsedOnMobile: false,
                firstLayerId: "layer1",
                gpcDntLayerId: nil,
                consentLayers: ["layer1": layer]
            )

            return ConsentConfig(
                version: "1.0",
                consentContainerVersionId: "container1",
                dgCustomerId: "test-customer",
                publishDate: 0,
                dch: "categorize",
                dc: "dg-category-essential",
                privacyDomain: "test.com",
                plugins: Plugins(
                    scriptControl: false,
                    allCookieSubdomains: false,
                    cookieBlocking: false,
                    localStorageBlocking: false,
                    syncOTConsent: false
                ),
                testMode: false,
                ignoreDoNotTrack: false,
                trackingDetailsUrl: "https://example.com/tracking",
                consentMode: "optin",
                showBanner: true,
                consentPolicy: ConsentPolicy(name: "Test", default: true),
                gppUsNat: false,
                initialCategories: InitialCategories(
                    respectGpc: false,
                    respectDnt: false,
                    respectOptout: false,
                    initial: [],
                    gpc: [],
                    optout: []
                ),
                layout: layout
            )
        }

        // swiftlint:disable:next function_body_length
        static func createConfigWithCategories() -> ConsentConfig {
            let categories = [
                ConsentLayerCategory(
                    id: "essential",
                    consentCategoryId: "cat1",
                    order: 1,
                    hidden: false,
                    primitive: "essential",
                    alwaysOn: true,
                    gtmKey: "category_essential",
                    uuids: [],
                    cookiePatterns: [],
                    translations: [
                        "en": CategoryTranslation(
                            id: nil,
                            locale: "en",
                            name: "Essential",
                            description: nil,
                            essentialLabel: nil,
                            trackingDetailsLink: nil
                        ),
                    ],
                    showTrackingDetailsLink: false
                ),
                ConsentLayerCategory(
                    id: "marketing",
                    consentCategoryId: "cat2",
                    order: 2,
                    hidden: false,
                    primitive: "marketing",
                    alwaysOn: false,
                    gtmKey: "category_marketing",
                    uuids: [],
                    cookiePatterns: [],
                    translations: [
                        "en": CategoryTranslation(
                            id: nil,
                            locale: "en",
                            name: "Marketing",
                            description: nil,
                            essentialLabel: nil,
                            trackingDetailsLink: nil
                        ),
                    ],
                    showTrackingDetailsLink: false
                ),
            ]

            let element = ConsentLayerElement(
                id: "categories",
                order: 1,
                type: "category",
                style: nil,
                buttonAction: nil,
                targetConsentLayer: nil,
                categories: nil,
                links: nil,
                consentLayerCategories: categories,
                showTrackingDetailsLink: nil,
                consentLayerCategoriesConfigId: nil,
                trackingDetailsLinkTranslations: nil,
                showIcon: nil,
                consentLayerBrowserSignalNoticeConfigId: nil,
                browserSignalNoticeTranslations: nil,
                showTrackingServices: nil,
                showCookies: nil,
                showIcons: nil,
                groupByVendor: nil,
                translations: nil
            )

            let layer = ConsentLayer(
                id: "layer1",
                name: "First Layer",
                theme: "neutral",
                position: "bottom",
                showCloseButton: true,
                bannerApiId: "first",
                elements: [element]
            )

            let layout = Layout(
                id: "layout1",
                name: "Test Layout",
                description: nil,
                status: "published",
                defaultLayout: true,
                collapsedOnMobile: false,
                firstLayerId: "layer1",
                gpcDntLayerId: nil,
                consentLayers: ["layer1": layer]
            )

            return ConsentConfig(
                version: "1.0",
                consentContainerVersionId: "container1",
                dgCustomerId: "test-customer",
                publishDate: 0,
                dch: "categorize",
                dc: "dg-category-essential",
                privacyDomain: "test.com",
                plugins: Plugins(
                    scriptControl: false,
                    allCookieSubdomains: false,
                    cookieBlocking: false,
                    localStorageBlocking: false,
                    syncOTConsent: false
                ),
                testMode: false,
                ignoreDoNotTrack: false,
                trackingDetailsUrl: "https://example.com/tracking",
                consentMode: "optin",
                showBanner: true,
                consentPolicy: ConsentPolicy(name: "Test", default: true),
                gppUsNat: false,
                initialCategories: InitialCategories(
                    respectGpc: false,
                    respectDnt: false,
                    respectOptout: false,
                    initial: ["category_essential", "category_marketing"],
                    gpc: [],
                    optout: []
                ),
                layout: layout
            )
        }

        // swiftlint:disable:next function_body_length
        static func createConfigWithLink() -> ConsentConfig {
            let element = ConsentLayerElement(
                id: "link1",
                order: 1,
                type: "link",
                style: nil,
                buttonAction: nil,
                targetConsentLayer: nil,
                categories: nil,
                links: nil,
                consentLayerCategories: nil,
                showTrackingDetailsLink: nil,
                consentLayerCategoriesConfigId: nil,
                trackingDetailsLinkTranslations: nil,
                showIcon: nil,
                consentLayerBrowserSignalNoticeConfigId: nil,
                browserSignalNoticeTranslations: nil,
                showTrackingServices: nil,
                showCookies: nil,
                showIcons: nil,
                groupByVendor: nil,
                translations: [
                    "en": ElementTranslation(
                        id: nil,
                        locale: "en",
                        value: nil,
                        text: "Privacy Policy",
                        url: "https://example.com/privacy"
                    ),
                ]
            )

            let layer = ConsentLayer(
                id: "layer1",
                name: "First Layer",
                theme: "neutral",
                position: "bottom",
                showCloseButton: true,
                bannerApiId: "first",
                elements: [element]
            )

            let layout = Layout(
                id: "layout1",
                name: "Test Layout",
                description: nil,
                status: "published",
                defaultLayout: true,
                collapsedOnMobile: false,
                firstLayerId: "layer1",
                gpcDntLayerId: nil,
                consentLayers: ["layer1": layer]
            )

            return ConsentConfig(
                version: "1.0",
                consentContainerVersionId: "container1",
                dgCustomerId: "test-customer",
                publishDate: 0,
                dch: "categorize",
                dc: "dg-category-essential",
                privacyDomain: "test.com",
                plugins: Plugins(
                    scriptControl: false,
                    allCookieSubdomains: false,
                    cookieBlocking: false,
                    localStorageBlocking: false,
                    syncOTConsent: false
                ),
                testMode: false,
                ignoreDoNotTrack: false,
                trackingDetailsUrl: "https://example.com/tracking",
                consentMode: "optin",
                showBanner: true,
                consentPolicy: ConsentPolicy(name: "Test", default: true),
                gppUsNat: false,
                initialCategories: InitialCategories(
                    respectGpc: false,
                    respectDnt: false,
                    respectOptout: false,
                    initial: [],
                    gpc: [],
                    optout: []
                ),
                layout: layout
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
                action: "accept_all", text: "Accept All"
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
                action: "reject_all", text: "Reject All"
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
                action: "save", text: "Save Preferences"
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
