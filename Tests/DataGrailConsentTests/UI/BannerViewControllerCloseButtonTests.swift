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

        func testFullScreenWithCloseButtonVisible() {
            let config = createConfigWithCloseButton(showCloseButton: true)
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .fullScreen,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let closeButton = findCloseButton(in: vc.view)
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

            let closeButton = findCloseButton(in: vc.view)
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

            let closeButton = findCloseButton(in: vc.view)
            XCTAssertNotNil(closeButton, "Close button should exist in view hierarchy")
            XCTAssertTrue(
                closeButton?.isHidden ?? false,
                "Close button should be hidden for layer2 with showCloseButton: false"
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
                theme: "neutral",
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
                theme: "neutral",
                position: "bottom",
                showCloseButton: showCloseButton,
                bannerApiId: id,
                elements: [element]
            )
        }

        private func findCloseButton(in view: UIView) -> UIButton? {
            findView(in: view) { view in
                guard let button = view as? UIButton else { return false }
                return button.title(for: .normal) == "✕"
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
