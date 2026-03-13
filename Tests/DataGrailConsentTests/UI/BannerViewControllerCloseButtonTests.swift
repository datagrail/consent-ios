#if canImport(UIKit)
    import XCTest

    @testable import DataGrailConsent

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

            let closeButton = findCloseButton(in: vc.view)
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

            let closeButton = findCloseButton(in: vc.view)
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

            let closeButton = findCloseButton(in: vc.view)
            XCTAssertNotNil(closeButton, "Close button should exist in view hierarchy")
            XCTAssertTrue(closeButton?.isHidden ?? false, "Close button should be hidden when showCloseButton is false")
        }

        func testLayerNavigationUpdatesCloseButtonVisibility() {
            let config = createConfigWithTwoLayers(
                layer1ShowCloseButton: true,
                layer2ShowCloseButton: false
            )
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let closeButton = findCloseButton(in: vc.view)
            XCTAssertFalse(closeButton?.isHidden ?? true, "Close button should initially be visible on layer1")

            // Navigate to layer2 which has showCloseButton: false
            let navigateButton = findButton(in: vc.view, withTitle: "Go to Layer 2")
            XCTAssertNotNil(navigateButton, "Navigate button should exist")
            navigateButton?.sendActions(for: .touchUpInside)

            XCTAssertTrue(closeButton?.isHidden ?? false, "Close button should be hidden after navigating to layer2")
        }

        // MARK: - Helper Methods

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
                theme: "neutral",
                position: "bottom",
                showCloseButton: showCloseButton,
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

        private func createConfigWithTwoLayers(
            layer1ShowCloseButton: Bool,
            layer2ShowCloseButton: Bool
        ) -> ConsentConfig {
            let navigateButton = ConsentLayerElement(
                id: "btn1",
                order: 1,
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
                        value: nil,
                        text: "Go to Layer 2",
                        url: nil
                    ),
                ]
            )

            let layer1 = ConsentLayer(
                id: "layer1",
                name: "First Layer",
                theme: "neutral",
                position: "bottom",
                showCloseButton: layer1ShowCloseButton,
                bannerApiId: "first",
                elements: [navigateButton]
            )

            let layer2Element = ConsentLayerElement(
                id: "text2",
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
                        value: "Layer 2 content",
                        text: nil,
                        url: nil
                    ),
                ]
            )

            let layer2 = ConsentLayer(
                id: "layer2",
                name: "Second Layer",
                theme: "neutral",
                position: "bottom",
                showCloseButton: layer2ShowCloseButton,
                bannerApiId: "second",
                elements: [layer2Element]
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
                consentLayers: ["layer1": layer1, "layer2": layer2]
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

        private func findCloseButton(in view: UIView) -> UIButton? {
            findView(in: view) { view in
                guard let button = view as? UIButton else { return false }
                return button.title(for: .normal) == "✕"
            } as? UIButton
        }

        private func findButton(in view: UIView, withTitle title: String) -> UIButton? {
            findView(in: view) { view in
                guard let button = view as? UIButton else { return false }
                return button.title(for: .normal) == title
            } as? UIButton
        }

        private func findView(in view: UIView, matching predicate: (UIView) -> Bool) -> UIView? {
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
    }
#endif
