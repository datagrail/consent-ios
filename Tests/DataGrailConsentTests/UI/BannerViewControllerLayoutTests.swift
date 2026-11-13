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

        /// Captures the blocks `viewWillTransition` registers so a test can run them after resizing the window.
        private final class StubTransitionCoordinator: NSObject, UIViewControllerTransitionCoordinator {
            private var alongside: ((UIViewControllerTransitionCoordinatorContext) -> Void)?
            private var completion: ((UIViewControllerTransitionCoordinatorContext) -> Void)?

            func runTransition() {
                alongside?(self)
                completion?(self)
            }

            @discardableResult
            func animate(
                alongsideTransition animation: ((UIViewControllerTransitionCoordinatorContext) -> Void)?,
                completion: ((UIViewControllerTransitionCoordinatorContext) -> Void)?
            ) -> Bool {
                alongside = animation
                self.completion = completion
                return true
            }

            @discardableResult
            func animateAlongsideTransition(
                in view: UIView?,
                animation: ((UIViewControllerTransitionCoordinatorContext) -> Void)?,
                completion: ((UIViewControllerTransitionCoordinatorContext) -> Void)?
            ) -> Bool {
                animate(alongsideTransition: animation, completion: completion)
            }

            func notifyWhenInteractionEnds(_ handler: @escaping (UIViewControllerTransitionCoordinatorContext) -> Void) {}
            func notifyWhenInteractionChanges(
                _ handler: @escaping (UIViewControllerTransitionCoordinatorContext) -> Void
            ) {}

            var isAnimated: Bool { true }
            var presentationStyle: UIModalPresentationStyle { .none }
            var initiallyInteractive: Bool { false }
            var isInterruptible: Bool { false }
            var isInteractive: Bool { false }
            var isCancelled: Bool { false }
            var transitionDuration: TimeInterval { 0 }
            var percentComplete: CGFloat { 1 }
            var completionVelocity: CGFloat { 1 }
            var completionCurve: UIView.AnimationCurve { .linear }
            var containerView: UIView { UIView() }
            var targetTransform: CGAffineTransform { .identity }
            func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? { nil }
            func view(forKey key: UITransitionContextViewKey) -> UIView? { nil }
        }

        private func assertScrollFractionSurvivesSizeChange(_ fraction: CGFloat) throws {
            let config = BannerAccessibilityTestHelpers.createConfigWithCategories()
            let vc = present(.fullScreen, config: config, size: CGSize(width: 400, height: 200))
            let scrollView = try XCTUnwrap(
                BannerAccessibilityTestHelpers.findView(in: vc.view) { $0 is UIScrollView } as? UIScrollView
            )
            let maxOffset = scrollView.contentSize.height - scrollView.bounds.height
            guard maxOffset > 0 else { return XCTFail("Content must be scrollable") }

            scrollView.contentOffset.y = fraction * maxOffset
            XCTAssertEqual(vc.scrollProgress(), fraction, accuracy: 0.001)

            let newSize = CGSize(width: 300, height: 150)
            let coordinator = StubTransitionCoordinator()
            vc.viewWillTransition(to: newSize, with: coordinator)
            window?.frame = CGRect(origin: .zero, size: newSize)
            coordinator.runTransition()

            let newMaxOffset = scrollView.contentSize.height - scrollView.bounds.height
            XCTAssertGreaterThan(newMaxOffset, 0)
            XCTAssertEqual(scrollView.contentOffset.y, fraction * newMaxOffset, accuracy: 1)
        }

        func testScrollPositionAtBottomSurvivesSizeChange() throws {
            try assertScrollFractionSurvivesSizeChange(1)
        }

        func testScrollPositionAtMidpointSurvivesSizeChange() throws {
            try assertScrollFractionSurvivesSizeChange(0.5)
        }
    }
#endif
