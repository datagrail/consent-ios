#if canImport(UIKit)
    import XCTest

    @testable import DataGrailConsent

    final class BannerViewControllerLayoutTests: XCTestCase {
        private let trailingInset: CGFloat = 60
        private var window: UIWindow?

        override func tearDown() {
            window?.isHidden = true
            window = nil
            super.tearDown()
        }

        private func present(
            _ displayStyle: BannerDisplayStyle,
            config: ConsentConfig,
            size: CGSize = CGSize(width: 400, height: 300)
        ) -> BannerViewController {
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: displayStyle,
                completion: { _ in }
            )
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = vc
            window.makeKeyAndVisible()
            self.window = window
            vc.view.layoutIfNeeded()
            return vc
        }

        private func assertCloseButtonInsideTrailingSafeArea(_ displayStyle: BannerDisplayStyle) throws {
            let config = BannerAccessibilityTestHelpers.createTestConfig()
            let vc = BannerViewController(
                config: config,
                initialPreferences: nil,
                displayStyle: displayStyle,
                completion: { _ in }
            )
            vc.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: trailingInset)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
            window.rootViewController = vc
            window.makeKeyAndVisible()
            self.window = window
            vc.view.layoutIfNeeded()

            let closeButton = try XCTUnwrap(
                BannerAccessibilityTestHelpers.findButton(in: vc.view, withAccessibilityLabel: "Close consent banner")
            )
            let frame = closeButton.convert(closeButton.bounds, to: vc.view)
            XCTAssertLessThanOrEqual(frame.maxX, vc.view.bounds.width - trailingInset)
        }

        func testFullScreenCloseButtonRespectsTrailingSafeArea() throws {
            try assertCloseButtonInsideTrailingSafeArea(.fullScreen)
        }

        func testModalCloseButtonRespectsTrailingSafeArea() throws {
            try assertCloseButtonInsideTrailingSafeArea(.modal)
        }

        func testScrollProgressSurvivesSizeChange() throws {
            let config = BannerAccessibilityTestHelpers.createConfigWithCategories()
            let vc = present(.fullScreen, config: config, size: CGSize(width: 400, height: 200))
            let scrollView = try XCTUnwrap(
                BannerAccessibilityTestHelpers.findView(in: vc.view) { $0 is UIScrollView } as? UIScrollView
            )
            let maxOffset = scrollView.contentSize.height - scrollView.bounds.height
            try XCTSkipIf(maxOffset <= 0, "Content must be scrollable")

            scrollView.contentOffset.y = maxOffset
            let progress = vc.scrollProgress()
            XCTAssertEqual(progress, 1, accuracy: 0.001)

            window?.frame = CGRect(x: 0, y: 0, width: 300, height: 150)
            vc.restoreScrollProgress(progress)

            let newMaxOffset = scrollView.contentSize.height - scrollView.bounds.height
            XCTAssertEqual(scrollView.contentOffset.y, newMaxOffset, accuracy: 1)
        }
    }
#endif
