#if canImport(UIKit)
    import XCTest

    @testable import DataGrailConsent

    /// Tests for rich text (HTML) rendering in BannerViewController text elements
    final class BannerViewControllerRichTextTests: XCTestCase {

        // MARK: - Plain Text Passthrough

        func testPlainText_SetsLabelText() {
            let config = createConfigWithText("We value your privacy")
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let label = findLabel(in: vc.view, withPlainText: "We value your privacy")
            XCTAssertNotNil(label, "Plain text should be rendered via label.text")
            XCTAssertEqual(label?.text, "We value your privacy")
        }

        func testPlainTextWithoutAngleBrackets_UsesPlainTextPath() {
            let config = createConfigWithText("No HTML here & that is fine")
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let label = findLabel(in: vc.view, withPlainText: "No HTML here & that is fine")
            XCTAssertNotNil(label, "Text without angle brackets should use plain text path")
        }

        // MARK: - HTML Rendering

        func testHTMLText_SetsAttributedText() {
            let htmlText = "<p>We use <b>cookies</b> to improve your experience.</p>"
            let config = createConfigWithText(htmlText)
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let label = findLabelWithAttributedText(in: vc.view)
            XCTAssertNotNil(label, "HTML text should be rendered via attributedText")
            XCTAssertNotNil(label?.attributedText, "Label should have attributedText set")

            let attrString = label?.attributedText
            XCTAssertTrue(
                attrString?.string.contains("cookies") ?? false,
                "Attributed string should contain the text content"
            )
        }

        // MARK: - Font and Color Preservation

        func testHTMLText_PreservesFont() {
            let htmlText = "<b>Important notice</b>"
            let config = createConfigWithText(htmlText)
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let label = findLabelWithAttributedText(in: vc.view)
            XCTAssertNotNil(label, "HTML text label should exist")

            guard let attrText = label?.attributedText, attrText.length > 0 else {
                XCTFail("Attributed text should not be empty")
                return
            }

            let font = attrText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
            XCTAssertNotNil(font, "Font attribute should be present")
            XCTAssertEqual(font?.pointSize, 16, "Font size should be preserved as 16pt")
        }

        func testHTMLText_PreservesColor() {
            let htmlText = "<em>Styled text</em>"
            let config = createConfigWithText(htmlText)
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let label = findLabelWithAttributedText(in: vc.view)
            XCTAssertNotNil(label, "HTML text label should exist")

            guard let attrText = label?.attributedText, attrText.length > 0 else {
                XCTFail("Attributed text should not be empty")
                return
            }

            let color = attrText.attribute(.foregroundColor, at: 0, effectiveRange: nil)
            XCTAssertNotNil(color, "Foreground color attribute should be present")
        }

        // MARK: - Accessibility

        func testHTMLText_StripsTagsForAccessibilityLabel() {
            let htmlText = "<p>We use <b>cookies</b> for <em>analytics</em>.</p>"
            let config = createConfigWithText(htmlText)
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let label = findLabelWithAttributedText(in: vc.view)
            XCTAssertNotNil(label, "HTML text label should exist")

            let accessibilityLabel = label?.accessibilityLabel ?? ""
            XCTAssertFalse(
                accessibilityLabel.contains("<"),
                "Accessibility label should not contain HTML tags"
            )
            XCTAssertTrue(
                accessibilityLabel.contains("cookies"),
                "Accessibility label should contain text content"
            )
        }

        // MARK: - Invalid HTML Fallback

        func testAngleBracketInPlainText_UsesPlainTextPath() {
            // Text that contains < but is not a valid HTML tag should use the plain text path
            let text = "Temperature < 100 degrees"
            let config = createConfigWithText(text)
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: .modal,
                completion: { _ in }
            )
            vc.loadViewIfNeeded()

            let label = findLabel(in: vc.view, withPlainText: text)
            XCTAssertNotNil(label, "Text with < but no HTML tags should use plain text path")
            XCTAssertEqual(label?.text, text, "The literal < should be preserved in plain text")
        }

        // MARK: - Helpers

        // swiftlint:disable:next function_body_length
        private func createConfigWithText(_ text: String) -> ConsentConfig {
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
                        value: text,
                        text: nil,
                        url: nil
                    ),
                ]
            )

            let layer = ConsentLayer(
                id: "layer1",
                name: "First Layer",
                position: "bottom",
                showCloseButton: false,
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

        private func findLabel(in view: UIView, withPlainText text: String) -> UILabel? {
            BannerAccessibilityTestHelpers.findView(in: view) { subview in
                guard let label = subview as? UILabel else { return false }
                return label.text == text
            } as? UILabel
        }

        private func findLabelWithAttributedText(in view: UIView) -> UILabel? {
            BannerAccessibilityTestHelpers.findView(in: view) { subview in
                guard let label = subview as? UILabel else { return false }
                guard let attr = label.attributedText else { return false }
                guard attr.length > 0 else { return false }
                // Check that it was explicitly set (has font attribute applied)
                let font = attr.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
                return font != nil
            } as? UILabel
        }

        private func findAnyLabel(in view: UIView, containingText text: String) -> UILabel? {
            BannerAccessibilityTestHelpers.findView(in: view) { subview in
                guard let label = subview as? UILabel else { return false }
                if let plainText = label.text, plainText.contains(text) {
                    return true
                }
                if let attrText = label.attributedText?.string, attrText.contains(text) {
                    return true
                }
                return false
            } as? UILabel
        }
    }
#endif
