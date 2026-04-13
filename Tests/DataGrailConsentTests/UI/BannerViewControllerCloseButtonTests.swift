#if canImport(UIKit)
    import XCTest

    @testable import DataGrailConsent

    // swiftlint:disable type_body_length
    final class BannerViewControllerCloseButtonTests: XCTestCase {

        func testModalWithCloseButtonHidden() {
            let config = createConfigWithCloseButton(showCloseButton: false)
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
            XCTAssertNotNil(closeButton, "Close button should exist in view hierarchy")
            XCTAssertTrue(closeButton?.isHidden ?? false, "Close button should be hidden when showCloseButton is false")
        }

        func testModalWithCloseButtonVisible() {
            let config = createConfigWithCloseButton(showCloseButton: true)
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
            XCTAssertNotNil(closeButton, "Close button should exist in view hierarchy")
            XCTAssertFalse(closeButton?.isHidden ?? true, "Close button should be visible when showCloseButton is true")
        }

        func testFullScreenWithCloseButtonHidden() {
            let config = createConfigWithCloseButton(showCloseButton: false)
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .fullScreen,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let closeButton = BannerAccessibilityTestHelpers.findButton(
                in: vc.view, withAccessibilityLabel: "Close consent banner"
            )
            XCTAssertNotNil(closeButton, "Close button should exist in view hierarchy")
            XCTAssertTrue(closeButton?.isHidden ?? false, "Close button should be hidden when showCloseButton is false")
        }

        func testFullScreenWithCloseButtonVisible() {
            let config = createConfigWithCloseButton(showCloseButton: true)
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .fullScreen,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let closeButton = BannerAccessibilityTestHelpers.findButton(
                in: vc.view, withAccessibilityLabel: "Close consent banner"
            )
            XCTAssertNotNil(closeButton, "Close button should exist in view hierarchy")
            XCTAssertFalse(closeButton?.isHidden ?? true, "Close button should be visible when showCloseButton is true")
        }

        func testMultipleLayersStartingWithCloseButtonVisible() {
            let config = createConfigWithTwoLayersHavingDifferentCloseButtonValues(firstLayerId: "layer1")

            // Start with layer1 which has showCloseButton: true
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
            XCTAssertNotNil(closeButton, "Close button should exist in view hierarchy")
            XCTAssertFalse(
                closeButton?.isHidden ?? true,
                "Close button should be visible for layer1 with showCloseButton: true"
            )
        }

        func testMultipleLayersStartingWithCloseButtonHidden() {
            let config = createConfigWithTwoLayersHavingDifferentCloseButtonValues(firstLayerId: "layer2")

            // Start with layer2 which has showCloseButton: false
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
            XCTAssertNotNil(closeButton, "Close button should exist in view hierarchy")
            XCTAssertTrue(
                closeButton?.isHidden ?? false,
                "Close button should be hidden for layer2 with showCloseButton: false"
            )
        }

        func testNavigationTogglesCloseButtonVisibility() {
            // Create config with navigation button to move between layers
            let config = createConfigWithNavigationBetweenLayers()

            // Start with layer1 which has showCloseButton: true
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
            XCTAssertNotNil(closeButton, "Close button should exist in view hierarchy")
            XCTAssertFalse(
                closeButton?.isHidden ?? true,
                "Close button should be visible initially on layer1 with showCloseButton: true"
            )

            // Find and tap the navigation button to go to layer2
            let navigationButton = findNavigationButton(in: vc.view)
            XCTAssertNotNil(navigationButton, "Navigation button should exist")

            // Simulate button tap by invoking the target-action directly
            if let target = navigationButton?.allTargets.first as? NSObject,
               let actions = navigationButton?.actions(forTarget: target, forControlEvent: .touchUpInside),
               let action = actions.first {
                _ = target.perform(Selector(action), with: navigationButton)
            }

            // After navigation to layer2 (which has showCloseButton: false), close button should be hidden
            XCTAssertTrue(
                closeButton?.isHidden ?? false,
                "Close button should be hidden after navigating to layer2 with showCloseButton: false"
            )
        }

        func testNavigationTogglesCloseButtonVisibilityReverse() {
            // Create config with reverse navigation (hidden -> visible)
            let config = createConfigWithReverseNavigation()

            // Start with layer2 which has showCloseButton: false
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
            XCTAssertNotNil(closeButton, "Close button should exist in view hierarchy")
            XCTAssertTrue(
                closeButton?.isHidden ?? false,
                "Close button should be hidden initially on layer2 with showCloseButton: false"
            )

            // Find and tap the navigation button to go to layer1
            let navigationButton = findReverseNavigationButton(in: vc.view)
            XCTAssertNotNil(navigationButton, "Navigation button should exist")

            // Simulate button tap by invoking the target-action directly
            if let target = navigationButton?.allTargets.first as? NSObject,
               let actions = navigationButton?.actions(forTarget: target, forControlEvent: .touchUpInside),
               let action = actions.first {
                _ = target.perform(Selector(action), with: navigationButton)
            }

            // After navigation to layer1 (which has showCloseButton: true), close button should be visible
            XCTAssertFalse(
                closeButton?.isHidden ?? true,
                "Close button should be visible after navigating to layer1 with showCloseButton: true"
            )
        }

        // MARK: - Helper Methods

        private func createConfig(
            consentLayers: [String: ConsentLayer],
            firstLayerId: String
        ) -> ConsentConfig {
            let layout = Layout(
                id: "layout1",
                name: "Test Layout",
                description: nil,
                status: "published",
                defaultLayout: true,
                collapsedOnMobile: false,
                firstLayerId: firstLayerId,
                gpcDntLayerId: nil,
                consentLayers: consentLayers
            )

            return ConsentConfig(
                version: "1.0",
                consentContainerVersionId: "container1",
                dgCustomerId: "test-customer",
                publishDate: 0,
                dch: "categorize",
                dc: "dg-category-essential",
                privacyDomain: "test.com",
                analyticsEndpoint: nil,
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

        private func createConfigWithCloseButton(showCloseButton: Bool) -> ConsentConfig {
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
                position: "bottom",
                showCloseButton: showCloseButton,
                bannerApiId: "first",
                elements: [element]
            )

            return createConfig(consentLayers: ["layer1": layer], firstLayerId: "layer1")
        }

        private func createConfigWithTwoLayersHavingDifferentCloseButtonValues(
            firstLayerId: String
        ) -> ConsentConfig {
            let layer1 = createLayer(
                id: "layer1",
                name: "First Layer",
                showCloseButton: true,
                content: "Layer 1 content"
            )

            let layer2 = createLayer(
                id: "layer2",
                name: "Second Layer",
                showCloseButton: false,
                content: "Layer 2 content"
            )

            return createConfig(
                consentLayers: ["layer1": layer1, "layer2": layer2],
                firstLayerId: firstLayerId
            )
        }

        private func createLayer(
            id: String,
            name: String,
            showCloseButton: Bool,
            content: String
        ) -> ConsentLayer {
            let element = ConsentLayerElement(
                id: id + "_text",
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
                        value: content,
                        text: nil,
                        url: nil
                    ),
                ]
            )

            return ConsentLayer(
                id: id,
                name: name,
                position: "bottom",
                showCloseButton: showCloseButton,
                bannerApiId: id,
                elements: [element]
            )
        }

        private func createConfigWithNavigationBetweenLayers() -> ConsentConfig {
            let layer1 = createLayerWithNavigation()
            let layer2 = createLayer(
                id: "layer2",
                name: "Second Layer",
                showCloseButton: false,
                content: "Layer 2 content"
            )

            return createConfig(
                consentLayers: ["layer1": layer1, "layer2": layer2],
                firstLayerId: "layer1"
            )
        }

        private func createLayerWithNavigation() -> ConsentLayer {
            let textElement = createTextElement(id: "layer1_text", value: "Layer 1 content")
            let navigationButtonElement = createNavigationElement()

            return ConsentLayer(
                id: "layer1",
                name: "First Layer",
                position: "bottom",
                showCloseButton: true,
                bannerApiId: "layer1",
                elements: [textElement, navigationButtonElement]
            )
        }

        private func createTextElement(id: String, value: String) -> ConsentLayerElement {
            ConsentLayerElement(
                id: id,
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
                        value: value,
                        text: nil,
                        url: nil
                    ),
                ]
            )
        }

        private func createNavigationElement() -> ConsentLayerElement {
            ConsentLayerElement(
                id: "nav_button",
                order: 2,
                type: "button",
                style: nil,
                buttonAction: "navigate",
                targetConsentLayer: "layer2",
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
                        value: "Go to Layer 2",
                        text: nil,
                        url: nil
                    ),
                ]
            )
        }

        private func findNavigationButton(in view: UIView) -> UIButton? {
            BannerAccessibilityTestHelpers.findButton(in: view, withTitle: "Go to Layer 2")
        }

        private func createConfigWithReverseNavigation() -> ConsentConfig {
            // Layer1 with showCloseButton: true (destination)
            let layer1 = createLayer(
                id: "layer1",
                name: "First Layer",
                showCloseButton: true,
                content: "Layer 1 content"
            )

            // Layer2 with showCloseButton: false and navigation button back to layer1
            let textElement = createTextElement(id: "layer2_text", value: "Layer 2 content")
            let navigationButtonElement = createReverseNavigationElement()

            let layer2 = ConsentLayer(
                id: "layer2",
                name: "Second Layer",
                position: "bottom",
                showCloseButton: false,
                bannerApiId: "layer2",
                elements: [textElement, navigationButtonElement]
            )

            return createConfig(
                consentLayers: ["layer1": layer1, "layer2": layer2],
                firstLayerId: "layer2"
            )
        }

        private func createReverseNavigationElement() -> ConsentLayerElement {
            ConsentLayerElement(
                id: "nav_button_back",
                order: 2,
                type: "button",
                style: nil,
                buttonAction: "navigate",
                targetConsentLayer: "layer1",
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
                        value: "Go to Layer 1",
                        text: nil,
                        url: nil
                    ),
                ]
            )
        }

        private func findReverseNavigationButton(in view: UIView) -> UIButton? {
            BannerAccessibilityTestHelpers.findButton(in: view, withTitle: "Go to Layer 1")
        }

    }
#endif
