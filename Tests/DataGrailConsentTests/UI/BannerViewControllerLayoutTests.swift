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

        /// Same range the production code uses, so an inset error in it is not masked by matching zero insets.
        private func maxOffsetY(_ scrollView: UIScrollView) -> CGFloat {
            let inset = scrollView.adjustedContentInset
            return scrollView.contentSize.height + inset.top + inset.bottom - scrollView.bounds.height
        }

        private func scrollToBottom(_ scrollView: UIScrollView) {
            scrollView.contentOffset.y = maxOffsetY(scrollView) - scrollView.adjustedContentInset.top
        }

        private func assertAtBottom(_ scrollView: UIScrollView, file: StaticString = #filePath, line: UInt = #line) {
            let offset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            XCTAssertEqual(offset, maxOffsetY(scrollView), accuracy: 1, file: file, line: line)
        }

        private func presentScrollable() throws -> (BannerViewController, UIScrollView) {
            let config = BannerAccessibilityTestHelpers.createConfigWithCategories()
            let vc = present(.fullScreen, config: config, size: CGSize(width: 400, height: 200))
            let scrollView = try XCTUnwrap(
                BannerAccessibilityTestHelpers.findView(in: vc.view) { $0 is UIScrollView } as? UIScrollView
            )
            return (vc, scrollView)
        }

        private func startTransition(_ vc: BannerViewController) -> StubTransitionCoordinator {
            let newSize = CGSize(width: 300, height: 150)
            let coordinator = StubTransitionCoordinator()
            vc.viewWillTransition(to: newSize, with: coordinator)
            window?.frame = CGRect(origin: .zero, size: newSize)
            return coordinator
        }

        /// A layout pass that changes nothing, like the ones UIKit runs between a transition and a late inset.
        private func runNoOpLayout(_ vc: BannerViewController) {
            vc.view.setNeedsLayout()
            vc.view.layoutIfNeeded()
        }

        private func applyLateBottomInset(_ vc: BannerViewController) {
            vc.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 21, right: 0)
            vc.view.layoutIfNeeded()
        }

        private func assertScrollFractionSurvivesSizeChange(
            _ fraction: CGFloat, contentInset: UIEdgeInsets = .zero
        ) throws {
            let (vc, scrollView) = try presentScrollable()
            scrollView.contentInset = contentInset
            vc.view.layoutIfNeeded()
            guard maxOffsetY(scrollView) > 0 else { return XCTFail("Content must be scrollable") }

            scrollView.contentOffset.y = fraction * maxOffsetY(scrollView) - scrollView.adjustedContentInset.top
            XCTAssertEqual(vc.scrollProgress(), fraction, accuracy: 0.001)

            startTransition(vc).runTransition()

            let newMaxOffset = maxOffsetY(scrollView)
            XCTAssertGreaterThan(newMaxOffset, 0)
            let offset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            XCTAssertEqual(offset, fraction * newMaxOffset, accuracy: 1)
        }

        func testScrollPositionAtBottomSurvivesSizeChange() throws {
            try assertScrollFractionSurvivesSizeChange(1)
        }

        func testScrollPositionAtMidpointSurvivesSizeChange() throws {
            try assertScrollFractionSurvivesSizeChange(
                0.5, contentInset: UIEdgeInsets(top: 10, left: 0, bottom: 30, right: 0)
            )
        }

        /// The home-indicator inset can arrive after the transition completes, with unrelated layouts in between;
        /// the bottom must still be the bottom.
        func testScrollPositionAtBottomSurvivesLateBottomInset() throws {
            let (vc, scrollView) = try presentScrollable()
            scrollToBottom(scrollView)

            startTransition(vc).runTransition()
            runNoOpLayout(vc)
            applyLateBottomInset(vc)

            assertAtBottom(scrollView)
        }

        /// An earlier transition's completion, landing while a later one is still running, must not end the restore.
        func testOverlappingTransitionsKeepScrollPosition() throws {
            let (vc, scrollView) = try presentScrollable()
            scrollToBottom(scrollView)

            let first = startTransition(vc)
            let second = StubTransitionCoordinator()
            vc.viewWillTransition(to: CGSize(width: 350, height: 160), with: second)
            window?.frame = CGRect(origin: .zero, size: CGSize(width: 350, height: 160))
            first.runTransition()
            runNoOpLayout(vc)
            second.runTransition()
            applyLateBottomInset(vc)

            assertAtBottom(scrollView)
        }

        /// Once the user moves the scroll position by any means (here a programmatic scroll, as a status-bar tap
        /// or VoiceOver scroll would), a late inset change must not pull it back.
        func testUserScrollEndsPendingRestore() throws {
            let (vc, scrollView) = try presentScrollable()
            scrollToBottom(scrollView)

            startTransition(vc).runTransition()
            scrollView.contentOffset.y = -scrollView.adjustedContentInset.top
            applyLateBottomInset(vc)

            XCTAssertEqual(scrollView.contentOffset.y, -scrollView.adjustedContentInset.top, accuracy: 1)
        }
    }
#endif
