#if canImport(UIKit)
import Testing
import UIKit
@testable import NavigationStackController

@MainActor
struct UIKitGestureTests {
    @Test func physicalPanDirectionRespectsLayoutDirection() throws {
        let rightward = CGPoint(x: 100, y: 5)
        let leftward = CGPoint(x: -100, y: 5)
        #expect(try #require(NavigationStackPan(velocity: rightward, width: 320, layoutDirection: .leftToRight)).operation == .back)
        #expect(try #require(NavigationStackPan(velocity: leftward, width: 320, layoutDirection: .leftToRight)).operation == .forward)
        #expect(try #require(NavigationStackPan(velocity: rightward, width: 320, layoutDirection: .rightToLeft)).operation == .forward)
        #expect(try #require(NavigationStackPan(velocity: leftward, width: 320, layoutDirection: .rightToLeft)).operation == .back)
    }

    @Test func verticalAndUnlaidOutPansDoNotNavigate() {
        #expect(NavigationStackPan(velocity: CGPoint(x: 30, y: 50), width: 320, layoutDirection: .leftToRight) == nil)
        #expect(NavigationStackPan(velocity: CGPoint(x: 30, y: 30), width: 320, layoutDirection: .leftToRight) == nil)
        #expect(NavigationStackPan(velocity: .zero, width: 320, layoutDirection: .leftToRight) == nil)
        #expect(NavigationStackPan(velocity: CGPoint(x: 100, y: 0), width: 0, layoutDirection: .leftToRight) == nil)
    }

    @Test func reversalKeepsTheInitialOperationAndClampsProgress() throws {
        let pan = try #require(NavigationStackPan(
            velocity: CGPoint(x: -100, y: 0), width: 320, layoutDirection: .leftToRight
        ))
        #expect(pan.progress(translation: CGPoint(x: -160, y: 0)) == 0.5)
        #expect(pan.progress(translation: CGPoint(x: 40, y: 0)) == 0)
        #expect(pan.progress(translation: CGPoint(x: -400, y: 0)) == 1)
        #expect(pan.operation == .forward)
    }

    @Test func projectedVelocityCanFinishAShortPanOrCancelAReversedPan() throws {
        let pan = try #require(NavigationStackPan(
            velocity: CGPoint(x: 100, y: 0), width: 320, layoutDirection: .leftToRight
        ))
        #expect(pan.completes(
            translation: CGPoint(x: 20, y: 0), velocity: CGPoint(x: 800, y: 0),
            completionDistance: 187.5, maximumThreshold: 0.5, projectionDuration: 0.3
        ))
        #expect(!pan.completes(
            translation: CGPoint(x: 200, y: 0), velocity: CGPoint(x: -400, y: 0),
            completionDistance: 187.5, maximumThreshold: 0.5, projectionDuration: 0.3
        ))
    }

    @Test func completionDistanceRemainsBoundedOnWideAndNarrowViews() throws {
        let narrow = try #require(NavigationStackPan(
            velocity: CGPoint(x: -100, y: 0), width: 200, layoutDirection: .leftToRight
        ))
        let wide = try #require(NavigationStackPan(
            velocity: CGPoint(x: -100, y: 0), width: 1000, layoutDirection: .leftToRight
        ))
        #expect(narrow.completes(
            translation: CGPoint(x: -110, y: 0), velocity: .zero,
            completionDistance: 187.5, maximumThreshold: 0.5, projectionDuration: 0.3
        ))
        #expect(!wide.completes(
            translation: CGPoint(x: -110, y: 0), velocity: .zero,
            completionDistance: 187.5, maximumThreshold: 0.5, projectionDuration: 0.3
        ))
        #expect(wide.completes(
            translation: CGPoint(x: -190, y: 0), velocity: .zero,
            completionDistance: 187.5, maximumThreshold: 0.5, projectionDuration: 0.3
        ))
    }

    @Test func scrollArbitrationRespectsBothInsetBoundaries() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentSize = CGSize(width: 640, height: 480)
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 30)

        scrollView.contentOffset.x = -20
        #expect(!NavigationStackGestureController.canScroll(scrollView, horizontalDirection: 1))
        #expect(NavigationStackGestureController.canScroll(scrollView, horizontalDirection: -1))
        scrollView.contentOffset.x = 100
        #expect(NavigationStackGestureController.canScroll(scrollView, horizontalDirection: 1))
        #expect(NavigationStackGestureController.canScroll(scrollView, horizontalDirection: -1))
        scrollView.contentOffset.x = 350
        #expect(NavigationStackGestureController.canScroll(scrollView, horizontalDirection: 1))
        #expect(!NavigationStackGestureController.canScroll(scrollView, horizontalDirection: -1))
    }

    @Test func verticalAndDisabledScrollViewsDoNotClaimHorizontalNavigation() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentSize = CGSize(width: 320, height: 1000)
        scrollView.alwaysBounceHorizontal = true
        #expect(!NavigationStackGestureController.canScroll(scrollView, horizontalDirection: 1))
        #expect(!NavigationStackGestureController.canScroll(scrollView, horizontalDirection: -1))

        scrollView.contentSize.width = 1000
        scrollView.contentOffset.x = 100
        scrollView.isScrollEnabled = false
        #expect(!NavigationStackGestureController.canScroll(scrollView, horizontalDirection: 1))
    }
}
#endif
