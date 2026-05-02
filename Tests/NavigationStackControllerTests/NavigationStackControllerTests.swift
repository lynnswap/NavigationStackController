import AppKit
import Testing
@testable import NavigationStackController

@MainActor
@Test func initializesWithRootViewController() {
    let rootViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    #expect(navigationController.viewControllers.count == 1)
    #expect(navigationController.topViewController === rootViewController)
    #expect(navigationController.canGoBack == false)
    #expect(navigationController.canGoForward == false)
}

@MainActor
@Test func pushClearsForwardHistory() {
    let rootViewController = TestViewController()
    let firstViewController = TestViewController()
    let secondViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    navigationController.pushViewController(firstViewController, animated: false)
    let poppedViewController = navigationController.popViewController(animated: false)
    navigationController.pushViewController(secondViewController, animated: false)

    #expect(poppedViewController === firstViewController)
    #expect(navigationController.viewControllers.map(ObjectIdentifier.init) == [rootViewController, secondViewController].map(ObjectIdentifier.init))
    #expect(navigationController.forwardViewControllers.isEmpty)
    #expect(navigationController.children.contains { $0 === rootViewController })
    #expect(navigationController.children.contains { $0 === secondViewController })
    #expect(!navigationController.children.contains { $0 === firstViewController })
}

@MainActor
@Test func pushRejectsDuplicateViewControllerInstances() {
    let rootViewController = TestViewController()
    let firstViewController = TestViewController()
    let secondViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    navigationController.pushViewController(firstViewController, animated: false)
    navigationController.pushViewController(firstViewController, animated: false)

    #expect(identifiers(navigationController.viewControllers) == identifiers([rootViewController, firstViewController]))

    navigationController.pushViewController(secondViewController, animated: false)
    navigationController.goBack(animated: false)
    navigationController.pushViewController(secondViewController, animated: false)

    #expect(identifiers(navigationController.viewControllers) == identifiers([rootViewController, firstViewController]))
    #expect(identifiers(navigationController.forwardViewControllers) == identifiers([secondViewController]))
}

@MainActor
@Test func setViewControllersRejectsDuplicateViewControllerInstances() {
    let rootViewController = TestViewController()
    let firstViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    navigationController.setViewControllers([rootViewController, firstViewController, firstViewController], animated: false)

    #expect(identifiers(navigationController.viewControllers) == identifiers([rootViewController]))
    #expect(NavigationStackController.hasUniqueViewControllerInstances([rootViewController, firstViewController]))
    #expect(!NavigationStackController.hasUniqueViewControllerInstances([rootViewController, firstViewController, firstViewController]))
}

@MainActor
@Test func willShowReentrantNavigationIsIgnored() {
    let rootViewController = TestViewController()
    let pushedViewController = TestViewController()
    let reentrantViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)
    let delegate = ReentrantNavigationDelegate()

    _ = navigationController.view
    delegate.onWillShow = { controller in
        controller.pushViewController(reentrantViewController, animated: false)
    }
    navigationController.delegate = delegate

    navigationController.pushViewController(pushedViewController, animated: false)

    #expect(navigationController.topViewController === pushedViewController)
    #expect(identifiers(navigationController.viewControllers) == identifiers([rootViewController, pushedViewController]))
    #expect(!navigationController.children.contains { $0 === reentrantViewController })
}

@MainActor
@Test func backAndForwardMoveViewControllersBetweenStacks() {
    let rootViewController = TestViewController()
    let firstViewController = TestViewController()
    let secondViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    navigationController.pushViewController(firstViewController, animated: false)
    navigationController.pushViewController(secondViewController, animated: false)

    let poppedViewController = navigationController.goBack(animated: false)
    #expect(poppedViewController === secondViewController)
    #expect(navigationController.topViewController === firstViewController)
    #expect(navigationController.forwardViewControllers.last === secondViewController)

    let restoredViewController = navigationController.goForward(animated: false)
    #expect(restoredViewController === secondViewController)
    #expect(navigationController.topViewController === secondViewController)
    #expect(navigationController.forwardViewControllers.isEmpty)
}

@MainActor
@Test func animatedBackUpdatesHistoryBeforeWillShow() {
    let rootViewController = TestViewController()
    let firstViewController = TestViewController()
    let secondViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)
    let delegate = ReentrantNavigationDelegate()
    var observedTopViewController: NSViewController?
    var observedCanGoForward = false
    var observedForwardViewController: NSViewController?

    navigationController.transitionDuration = 0
    navigationController.pushViewController(firstViewController, animated: false)
    navigationController.pushViewController(secondViewController, animated: false)
    _ = navigationController.view
    delegate.onWillShow = { controller in
        observedTopViewController = controller.topViewController
        observedCanGoForward = controller.canGoForward
        observedForwardViewController = controller.forwardViewControllers.first
    }
    navigationController.delegate = delegate

    #expect(navigationController.goBack(animated: true) === secondViewController)
    #expect(observedTopViewController === firstViewController)
    #expect(observedCanGoForward)
    #expect(observedForwardViewController === secondViewController)
    #expect(navigationController.topViewController === firstViewController)
}

@MainActor
@Test func animatedForwardUpdatesHistoryBeforeWillShow() {
    let rootViewController = TestViewController()
    let firstViewController = TestViewController()
    let secondViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)
    let delegate = ReentrantNavigationDelegate()
    var observedTopViewController: NSViewController?
    var observedCanGoForward = true

    navigationController.transitionDuration = 0
    navigationController.pushViewController(firstViewController, animated: false)
    navigationController.pushViewController(secondViewController, animated: false)
    _ = navigationController.view
    navigationController.goBack(animated: false)
    delegate.onWillShow = { controller in
        observedTopViewController = controller.topViewController
        observedCanGoForward = controller.canGoForward
    }
    navigationController.delegate = delegate

    #expect(navigationController.goForward(animated: true) === secondViewController)
    #expect(observedTopViewController === secondViewController)
    #expect(!observedCanGoForward)
    #expect(navigationController.topViewController === secondViewController)
}

@MainActor
@Test func loadingViewInstallsTopViewController() {
    let rootViewController = TestViewController()
    let pushedViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    navigationController.pushViewController(pushedViewController, animated: false)
    _ = navigationController.view

    #expect(navigationController.view.subviews.contains { $0 === pushedViewController.view })
    #expect(!navigationController.view.subviews.contains { $0 === rootViewController.view })
}

@MainActor
@Test func repeatedBackForwardKeepsAdjacentHistoryOrder() {
    let viewControllers = (1...6).map { _ in TestViewController() }
    let navigationController = NavigationStackController(rootViewController: viewControllers[0])

    for viewController in viewControllers.dropFirst() {
        navigationController.pushViewController(viewController, animated: false)
    }

    for _ in 0..<5 {
        #expect(navigationController.topViewController === viewControllers[5])
        #expect(navigationController.goBack(animated: false) === viewControllers[5])
        #expect(navigationController.topViewController === viewControllers[4])
        #expect(navigationController.goForward(animated: false) === viewControllers[5])
    }

    #expect(navigationController.goBack(animated: false) === viewControllers[5])
    #expect(navigationController.goBack(animated: false) === viewControllers[4])
    #expect(navigationController.goBack(animated: false) === viewControllers[3])
    #expect(navigationController.topViewController === viewControllers[2])
    #expect(navigationController.goForward(animated: false) === viewControllers[3])
    #expect(navigationController.topViewController === viewControllers[3])
}

@MainActor
@Test func multipleBacksExposeForwardHistoryInNavigationOrder() {
    let viewControllers = (1...4).map { _ in TestViewController() }
    let navigationController = NavigationStackController(rootViewController: viewControllers[0])

    for viewController in viewControllers.dropFirst() {
        navigationController.pushViewController(viewController, animated: false)
    }

    #expect(navigationController.goBack(animated: false) === viewControllers[3])
    #expect(navigationController.goBack(animated: false) === viewControllers[2])
    #expect(identifiers(navigationController.forwardViewControllers) == identifiers([viewControllers[2], viewControllers[3]]))
    #expect(navigationController.goForward(animated: false) === viewControllers[2])
}

@MainActor
@Test func popToRootMovesPoppedControllersIntoForwardHistoryInNavigationOrder() {
    let viewControllers = (1...4).map { _ in TestViewController() }
    let navigationController = NavigationStackController(rootViewController: viewControllers[0])

    for viewController in viewControllers.dropFirst() {
        navigationController.pushViewController(viewController, animated: false)
    }

    let poppedViewControllers = navigationController.popToRootViewController(animated: false)

    #expect(identifiers(poppedViewControllers) == identifiers(Array(viewControllers[1...3])))
    #expect(identifiers(navigationController.forwardViewControllers) == identifiers(Array(viewControllers[1...3])))
    #expect(navigationController.goForward(animated: false) === viewControllers[1])
}

@MainActor
@Test func setViewControllersClearsForwardHistoryAndReconcilesChildren() {
    let rootViewController = TestViewController()
    let pushedViewController = TestViewController()
    let replacementRootViewController = TestViewController()
    let replacementTopViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    navigationController.pushViewController(pushedViewController, animated: false)
    navigationController.goBack(animated: false)
    navigationController.setViewControllers([replacementRootViewController, replacementTopViewController], animated: false)

    #expect(navigationController.forwardViewControllers.isEmpty)
    #expect(navigationController.topViewController === replacementTopViewController)
    #expect(identifiers(navigationController.children) == identifiers([replacementRootViewController, replacementTopViewController]))
}

@MainActor
@Test func animatedSetViewControllersKeepsOutgoingControllerContainedDuringWillShow() {
    let rootViewController = TestViewController()
    let outgoingViewController = TestViewController()
    let replacementRootViewController = TestViewController()
    let replacementTopViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)
    let delegate = ReentrantNavigationDelegate()
    var observedChildren: [NSViewController] = []

    navigationController.transitionDuration = 0
    navigationController.pushViewController(outgoingViewController, animated: false)
    _ = navigationController.view
    delegate.onWillShow = { controller in
        observedChildren = controller.children
    }
    navigationController.delegate = delegate

    navigationController.setViewControllers([replacementRootViewController, replacementTopViewController], animated: true)

    #expect(observedChildren.contains { $0 === outgoingViewController })
    #expect(observedChildren.contains { $0 === replacementRootViewController })
    #expect(observedChildren.contains { $0 === replacementTopViewController })
}

@MainActor
@Test func rightToLeftBackTransitionReversesFrameOffsets() {
    let fromViewController = TestViewController()
    let toViewController = TestViewController()
    let transition = NavigationStackController.Transition(
        from: fromViewController,
        to: toViewController,
        direction: .back,
        operation: .back
    )

    transition.apply(
        progress: 0.25,
        in: NSRect(x: 0, y: 0, width: 200, height: 100),
        parallaxFactor: 0.25,
        layoutDirection: .rightToLeft,
        animated: false
    )

    #expect(isApproximatelyEqual(fromViewController.view.frame.origin.x, -50))
    #expect(isApproximatelyEqual(toViewController.view.frame.origin.x, 37.5))
}

@Test func swipeStartClassifierRequiresHorizontalThresholdAndHysteresis() {
    let classifier = NavigationSwipeStartClassifier(minimumHorizontalDistance: 10, verticalHysteresis: 1.2)

    #expect(classifier.decision(deltaX: 9, deltaY: 0) == .pending)
    #expect(classifier.decision(deltaX: 12, deltaY: 11) == .pending)
    #expect(classifier.decision(deltaX: 12, deltaY: 4) == .start)
    #expect(classifier.decision(deltaX: 4, deltaY: 12) == .cancel)
}

@Test func swipePhaseDecisionFinishesAtPhysicalGestureEnd() {
    #expect(NavigationSwipePhaseDecision(phase: .ended, isComplete: false).shouldFinish)
    #expect(NavigationSwipePhaseDecision(phase: .cancelled, isComplete: false).shouldFinish)
    #expect(NavigationSwipePhaseDecision(phase: [], isComplete: true).shouldFinish)
    #expect(!NavigationSwipePhaseDecision(phase: [], isComplete: false).shouldFinish)
    #expect(!NavigationSwipePhaseDecision(phase: .mayBegin, isComplete: false).shouldFinish)
    #expect(!NavigationSwipePhaseDecision(phase: .ended, isComplete: false).isForcedCancellation)
    #expect(NavigationSwipePhaseDecision(phase: .cancelled, isComplete: false).isForcedCancellation)
    #expect(!NavigationSwipePhaseDecision(phase: .mayBegin, isComplete: false).isForcedCancellation)
}

private final class TestViewController: NSViewController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    }
}

private final class ReentrantNavigationDelegate: NavigationStackControllerDelegate {
    var onWillShow: ((NavigationStackController) -> Void)?

    func navigationStackController(_ controller: NavigationStackController, willShow viewController: NSViewController, operation: NavigationStackOperation, animated: Bool) {
        onWillShow?(controller)
    }
}

private func identifiers(_ viewControllers: [NSViewController]) -> [ObjectIdentifier] {
    viewControllers.map(ObjectIdentifier.init)
}

private func isApproximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 0.001) -> Bool {
    abs(lhs - rhs) <= tolerance
}
