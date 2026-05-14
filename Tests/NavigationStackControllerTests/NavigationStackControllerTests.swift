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
@Test func animatedBackKeepsOutgoingVisibleUntilAnimationCompletes() async throws {
    let rootViewController = TestViewController()
    let firstViewController = TestViewController()
    let secondViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    _ = navigationController.view
    navigationController.view.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
    navigationController.transitionDuration = 0.05
    navigationController.pushViewController(firstViewController, animated: false)
    navigationController.pushViewController(secondViewController, animated: false)

    #expect(navigationController.goBack(animated: true) === secondViewController)
    #expect(navigationController.topViewController === firstViewController)
    #expect(navigationController.visibleViewController === secondViewController)

    try await Task.sleep(nanoseconds: 150_000_000)

    #expect(navigationController.topViewController === firstViewController)
    #expect(navigationController.visibleViewController === firstViewController)
}

@MainActor
@Test func animatedPushKeepsOutgoingVisibleUntilAnimationCompletes() async throws {
    let rootViewController = TestViewController()
    let pushedViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    _ = navigationController.view
    navigationController.view.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
    navigationController.transitionDuration = 0.05

    navigationController.pushViewController(pushedViewController, animated: true)
    navigationController.view.layoutSubtreeIfNeeded()

    #expect(navigationController.topViewController === pushedViewController)
    #expect(navigationController.visibleViewController === rootViewController)

    try await Task.sleep(nanoseconds: 150_000_000)

    #expect(navigationController.topViewController === pushedViewController)
    #expect(navigationController.visibleViewController === pushedViewController)
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

@MainActor
@Test func backTransitionDoesNotExposeContainerBackgroundNearCompletion() {
    let fromViewController = TestViewController()
    let toViewController = TestViewController()
    let transition = NavigationStackController.Transition(
        from: fromViewController,
        to: toViewController,
        direction: .back,
        operation: .back
    )

    transition.apply(
        progress: 0.95,
        in: NSRect(x: 0, y: 0, width: 200, height: 100),
        parallaxFactor: 0.25,
        layoutDirection: .leftToRight,
        animated: false
    )

    #expect(toViewController.view.frame.maxX >= fromViewController.view.frame.minX)
}

@MainActor
@Test func backTransitionInstallsBackdropBehindParallaxedIncomingView() {
    let rootViewController = TestViewController()
    let pushedViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    _ = navigationController.view
    navigationController.view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
    navigationController.pushViewController(pushedViewController, animated: false)

    #expect(navigationController.beginSwipeGesture(direction: .back))
    defer {
        navigationController.endSwipeGesture(committed: false, duration: 0) { }
    }

    let subviews = navigationController.view.subviews
    #expect(subviews.count == 3)
    #expect(subviews[0] is NavigationTransitionBackdropView)
    let incomingTransitionView = subviews[1] as? NavigationTransitionContentView
    let outgoingTransitionView = subviews[2] as? NavigationTransitionContentView
    #expect(incomingTransitionView?.contentView === rootViewController.view)
    #expect(outgoingTransitionView?.contentView === pushedViewController.view)
    #expect(incomingTransitionView?.layer?.masksToBounds == true)
    #expect(outgoingTransitionView?.layer?.masksToBounds == true)
    #expect(isApproximatelyEqual(incomingTransitionView?.frame.origin.x ?? 0, -navigationController.parallaxFactor * 200))
    #expect(isApproximatelyEqual(rootViewController.view.frame.origin.x, 0))
}

@MainActor
@Test func backTransitionAnimatesHorizontalScrollViewThroughTransitionHost() {
    let rootViewController = HorizontalScrollRootViewController()
    let pushedViewController = HorizontalScrollRootViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    _ = navigationController.view
    navigationController.view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
    navigationController.pushViewController(pushedViewController, animated: false)

    #expect(navigationController.beginSwipeGesture(direction: .back))
    defer {
        navigationController.endSwipeGesture(committed: false, duration: 0) { }
    }

    navigationController.handleSwipeGesture(progress: 0.5)

    let subviews = navigationController.view.subviews
    #expect(subviews.count == 3)
    let incomingTransitionView = subviews[1] as? NavigationTransitionContentView
    let outgoingTransitionView = subviews[2] as? NavigationTransitionContentView
    #expect(incomingTransitionView?.contentView === rootViewController.view)
    #expect(outgoingTransitionView?.contentView === pushedViewController.view)
    #expect(rootViewController.view is NSScrollView)
    #expect(pushedViewController.view is NSScrollView)
    #expect(incomingTransitionView?.layer?.masksToBounds == true)
    #expect(outgoingTransitionView?.layer?.masksToBounds == true)
    #expect(isApproximatelyEqual(incomingTransitionView?.frame.origin.x ?? 0, -navigationController.parallaxFactor * 100))
    #expect(isApproximatelyEqual(outgoingTransitionView?.frame.origin.x ?? 0, 100))
    #expect(isApproximatelyEqual(rootViewController.view.frame.origin.x, 0))
    #expect(isApproximatelyEqual(pushedViewController.view.frame.origin.x, 0))
}

@Test func swipeStartClassifierRequiresHorizontalThresholdAndHysteresis() {
    let classifier = NavigationSwipeStartClassifier(minimumHorizontalDistance: 10, verticalHysteresis: 1.2)

    #expect(classifier.decision(deltaX: 4, deltaY: 2) == .pending)
    #expect(classifier.decision(deltaX: 9, deltaY: 0) == .pending)
    #expect(classifier.decision(deltaX: 12, deltaY: 11) == .pending)
    #expect(classifier.decision(deltaX: 12, deltaY: 4) == .start)
    #expect(classifier.decision(deltaX: 4, deltaY: 12) == .cancel)
}

@MainActor
@Test func swipeDirectionFollowsLayoutDirection() {
    let rootViewController = TestViewController()
    let pushedViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)
    let viewGestureController = NavigationViewGestureController(navigationController: navigationController)

    _ = navigationController.view
    navigationController.pushViewController(pushedViewController, animated: false)

    #expect(isBack(viewGestureController.navigationDirection(forSwipeGestureAmount: 0.1)))
    #expect(isForward(viewGestureController.navigationDirection(forSwipeGestureAmount: -0.1)))
}

@MainActor
@Test func horizontalScrollConflictResolverDefersOnlyWhenScrollViewCanMoveInSwipeDirection() {
    let scrollView = makeHorizontalTestScrollView(visibleWidth: 100, documentWidth: 300)

    #expect(!NavigationHorizontalScrollConflictResolver.canScrollHorizontally(scrollView, deltaX: 20))
    #expect(NavigationHorizontalScrollConflictResolver.canScrollHorizontally(scrollView, deltaX: -20))

    scrollView.contentView.scroll(to: NSPoint(x: 100, y: 0))
    scrollView.reflectScrolledClipView(scrollView.contentView)

    #expect(NavigationHorizontalScrollConflictResolver.canScrollHorizontally(scrollView, deltaX: 20))
    #expect(NavigationHorizontalScrollConflictResolver.canScrollHorizontally(scrollView, deltaX: -20))

    scrollView.contentView.scroll(to: NSPoint(x: 200, y: 0))
    scrollView.reflectScrolledClipView(scrollView.contentView)

    #expect(NavigationHorizontalScrollConflictResolver.canScrollHorizontally(scrollView, deltaX: 20))
    #expect(!NavigationHorizontalScrollConflictResolver.canScrollHorizontally(scrollView, deltaX: -20))
}

@MainActor
@Test func horizontalScrollConflictResolverFindsScrollableViewAtEventLocation() {
    let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
    let scrollView = makeHorizontalTestScrollView(visibleWidth: 100, documentWidth: 300)
    scrollView.frame.origin = NSPoint(x: 20, y: 10)
    containerView.addSubview(scrollView)

    let hitView = containerView.hitTest(NSPoint(x: 50, y: 40))

    #expect(!NavigationHorizontalScrollConflictResolver.canScrollHorizontally(from: hitView, inside: containerView, deltaX: 20))
    #expect(NavigationHorizontalScrollConflictResolver.canScrollHorizontally(from: hitView, inside: containerView, deltaX: -20))
}

@MainActor
@Test func rootScrollViewCanForwardSwipeTrackingThroughNavigationControllerResponder() {
    let rootViewController = TestViewController()
    let scrollRootViewController = HorizontalScrollRootViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    _ = navigationController.view
    navigationController.pushViewController(scrollRootViewController, animated: false)

    #expect(navigationController.wantsScrollEventsForSwipeTracking(on: .horizontal))
    #expect(navigationController.wantsForwardedScrollEvents(for: .horizontal))
    #expect(!navigationController.wantsScrollEventsForSwipeTracking(on: .vertical))
    #expect(!navigationController.wantsForwardedScrollEvents(for: .vertical))

    let trackingResponder = firstSwipeTrackingResponder(startingAt: scrollRootViewController.view, axis: .horizontal)
    let isNavigationTrackingResponder = trackingResponder === navigationController.view || trackingResponder === navigationController
    #expect(isNavigationTrackingResponder)
}

@MainActor
@Test func enclosingScrollViewCanAskNavigationContainerToHandleSwipeThroughLibrarySelector() {
    let rootViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)
    let enclosingScrollView = makeHorizontalTestScrollView(visibleWidth: 100, documentWidth: 300)
    let handleSwipeSelector = #selector(NavigationStackController.handleForwardedSwipe(with:ignoringHorizontalScrollViews:))

    _ = navigationController.view
    navigationController.view.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
    enclosingScrollView.documentView = navigationController.view

    #expect(navigationController.view.enclosingScrollView === enclosingScrollView)
    #expect(navigationController.view.responds(to: handleSwipeSelector))
    #expect(navigationController.responds(to: handleSwipeSelector))
}

@MainActor
@Test func pendingSwipeConsumesSmallBeganEventAtHorizontalEdge() {
    let rootViewController = TestViewController()
    let pushedViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    _ = navigationController.view
    navigationController.view.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
    navigationController.pushViewController(pushedViewController, animated: false)

    let didHandle = navigationController.handleForwardedSwipe(
        with: makeScrollWheelEvent(deltaX: 1, phase: .began),
        ignoringHorizontalScrollViews: false
    )

    #expect(didHandle)
    #expect(navigationController.isGestureEventMonitorInstalled)
    #expect(navigationController.topViewController === pushedViewController)
    #expect(navigationController.visibleViewController === pushedViewController)

    #expect(navigationController.finishActiveSwipeGesture(cancelled: false))
    #expect(!navigationController.isGestureEventMonitorInstalled)
}

@MainActor
@Test func librarySwipeSelectorCanCommitBackNavigationAfterSmallBeganEvent() {
    let rootViewController = TestViewController()
    let pushedViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    _ = navigationController.view
    navigationController.view.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
    navigationController.minimumSwipeAnimationDuration = 0
    navigationController.maximumSwipeAnimationDuration = 0
    navigationController.pushViewController(pushedViewController, animated: false)

    #expect(navigationController.handleForwardedSwipe(
        with: makeScrollWheelEvent(deltaX: 1, phase: .began),
        ignoringHorizontalScrollViews: false
    ))
    #expect(navigationController.handleForwardedSwipe(
        with: makeScrollWheelEvent(deltaX: 220, phase: .changed),
        ignoringHorizontalScrollViews: false
    ))
    #expect(navigationController.handleForwardedSwipe(
        with: makeScrollWheelEvent(deltaX: 0, momentumPhase: .began),
        ignoringHorizontalScrollViews: false
    ))

    RunLoop.current.run(until: Date().addingTimeInterval(0.01))

    #expect(navigationController.topViewController === rootViewController)
    #expect(navigationController.forwardViewControllers.last === pushedViewController)
}

@MainActor
@Test func pendingSwipeLocalMonitorCapturesNestedScrollViewContinuation() {
    let rootViewController = TestViewController()
    let scrollRootViewController = HorizontalScrollRootViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    _ = navigationController.view
    navigationController.view.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
    navigationController.minimumSwipeAnimationDuration = 0
    navigationController.maximumSwipeAnimationDuration = 0
    navigationController.pushViewController(scrollRootViewController, animated: false)

    #expect(navigationController.handleForwardedSwipe(
        with: makeScrollWheelEvent(deltaX: 1, phase: .began),
        ignoringHorizontalScrollViews: false
    ))
    #expect(navigationController.isGestureEventMonitorInstalled)

    #expect(navigationController.handleLocalGestureMonitorEvent(
        makeScrollWheelEvent(deltaX: 220, phase: .changed),
        requiringMatchingWindow: false
    ))
    #expect(navigationController.topViewController === scrollRootViewController)

    #expect(navigationController.handleLocalGestureMonitorEvent(
        makeScrollWheelEvent(deltaX: 0, momentumPhase: .began),
        requiringMatchingWindow: false
    ))
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))

    #expect(navigationController.topViewController === rootViewController)
    #expect(navigationController.forwardViewControllers.last === scrollRootViewController)
    #expect(!navigationController.isGestureEventMonitorInstalled)
}

@MainActor
@Test func touchEndFinishesSwipeWhenScrollWheelTerminalEventIsMissing() {
    let rootViewController = TestViewController()
    let pushedViewController = TestViewController()
    let nextViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    _ = navigationController.view
    navigationController.view.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
    navigationController.minimumSwipeAnimationDuration = 0
    navigationController.maximumSwipeAnimationDuration = 0
    navigationController.pushViewController(pushedViewController, animated: false)

    #expect(navigationController.handleForwardedSwipe(
        with: makeScrollWheelEvent(deltaX: 1, phase: .began),
        ignoringHorizontalScrollViews: false
    ))
    #expect(navigationController.handleForwardedSwipe(
        with: makeScrollWheelEvent(deltaX: 118, phase: .changed),
        ignoringHorizontalScrollViews: false
    ))

    #expect(navigationController.finishActiveSwipeGesture(cancelled: false))

    #expect(navigationController.topViewController === pushedViewController)
    #expect(navigationController.forwardViewControllers.isEmpty)

    navigationController.pushViewController(nextViewController, animated: false)
    #expect(navigationController.topViewController === nextViewController)
}

@MainActor
@Test func activeSwipeLocalMonitorConsumesScrollWheelFromNestedHorizontalScrollView() {
    let rootViewController = TestViewController()
    let scrollRootViewController = HorizontalScrollRootViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    _ = navigationController.view
    navigationController.view.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
    navigationController.minimumSwipeAnimationDuration = 0
    navigationController.maximumSwipeAnimationDuration = 0
    navigationController.pushViewController(scrollRootViewController, animated: false)

    #expect(navigationController.handleForwardedSwipe(
        with: makeScrollWheelEvent(deltaX: 1, phase: .began),
        ignoringHorizontalScrollViews: true
    ))
    #expect(navigationController.handleForwardedSwipe(
        with: makeScrollWheelEvent(deltaX: 118, phase: .changed),
        ignoringHorizontalScrollViews: true
    ))

    let scrollView = scrollRootViewController.view as! NSScrollView
    scrollView.contentView.scroll(to: NSPoint(x: 100, y: 0))
    scrollView.reflectScrolledClipView(scrollView.contentView)

    #expect(NavigationHorizontalScrollConflictResolver.canScrollHorizontally(scrollView, deltaX: 20))
    #expect(navigationController.handleLocalGestureMonitorEvent(
        makeScrollWheelEvent(deltaX: 20, phase: .changed),
        requiringMatchingWindow: false
    ))
    #expect(navigationController.topViewController === scrollRootViewController)
    #expect(navigationController.visibleViewController === scrollRootViewController)

    #expect(navigationController.finishActiveSwipeGesture(cancelled: true))
    #expect(navigationController.topViewController === scrollRootViewController)
}

@MainActor
@Test func changedPhaseSwipeCanStartAndMomentumCanFinishBackNavigation() {
    let rootViewController = TestViewController()
    let pushedViewController = TestViewController()
    let nextViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    _ = navigationController.view
    navigationController.view.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
    navigationController.minimumSwipeAnimationDuration = 0
    navigationController.maximumSwipeAnimationDuration = 0
    navigationController.pushViewController(pushedViewController, animated: false)

    navigationController.view.scrollWheel(with: makeScrollWheelEvent(deltaX: 220, phase: .changed))
    navigationController.view.scrollWheel(with: makeScrollWheelEvent(deltaX: 60, momentumPhase: .began))
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))

    #expect(navigationController.topViewController === rootViewController)
    #expect(navigationController.forwardViewControllers.last === pushedViewController)

    navigationController.pushViewController(nextViewController, animated: false)
    #expect(navigationController.topViewController === nextViewController)
}

@MainActor
@Test func cancelledChangedPhaseSwipeRestoresCurrentPageAndAllowsPush() {
    let rootViewController = TestViewController()
    let pushedViewController = TestViewController()
    let nextViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    _ = navigationController.view
    navigationController.view.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
    navigationController.minimumSwipeAnimationDuration = 0
    navigationController.maximumSwipeAnimationDuration = 0
    navigationController.pushViewController(pushedViewController, animated: false)

    navigationController.view.scrollWheel(with: makeScrollWheelEvent(deltaX: 120, phase: .changed))
    navigationController.view.scrollWheel(with: makeScrollWheelEvent(deltaX: 0, phase: .cancelled))

    #expect(navigationController.topViewController === pushedViewController)
    #expect(navigationController.forwardViewControllers.isEmpty)

    navigationController.pushViewController(nextViewController, animated: false)
    #expect(navigationController.topViewController === nextViewController)
}

@MainActor
@Test func changedPhaseSwipeWaitsForTerminalEventBeforeCancellingAndAllowsPush() async throws {
    let rootViewController = TestViewController()
    let pushedViewController = TestViewController()
    let nextViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    _ = navigationController.view
    navigationController.view.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
    navigationController.minimumSwipeAnimationDuration = 0
    navigationController.maximumSwipeAnimationDuration = 0
    navigationController.pushViewController(pushedViewController, animated: false)

    navigationController.view.scrollWheel(with: makeScrollWheelEvent(deltaX: 120, phase: .changed))
    try await Task.sleep(nanoseconds: 350_000_000)

    #expect(navigationController.topViewController === pushedViewController)
    #expect(navigationController.forwardViewControllers.isEmpty)

    navigationController.pushViewController(nextViewController, animated: false)
    #expect(navigationController.topViewController === pushedViewController)

    navigationController.view.scrollWheel(with: makeScrollWheelEvent(deltaX: 0, phase: .cancelled))

    navigationController.pushViewController(nextViewController, animated: false)
    #expect(navigationController.topViewController === nextViewController)
}

@MainActor
@Test func changedPhaseSwipeWaitsForMomentumBeforeCompletingAndAllowsPush() async throws {
    let rootViewController = TestViewController()
    let pushedViewController = TestViewController()
    let nextViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    _ = navigationController.view
    navigationController.view.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
    navigationController.minimumSwipeAnimationDuration = 0
    navigationController.maximumSwipeAnimationDuration = 0
    navigationController.pushViewController(pushedViewController, animated: false)

    navigationController.view.scrollWheel(with: makeScrollWheelEvent(deltaX: 220, phase: .changed))
    try await Task.sleep(nanoseconds: 350_000_000)

    #expect(navigationController.topViewController === pushedViewController)
    #expect(navigationController.forwardViewControllers.isEmpty)

    navigationController.view.scrollWheel(with: makeScrollWheelEvent(deltaX: 60, momentumPhase: .began))

    #expect(navigationController.topViewController === rootViewController)
    #expect(navigationController.forwardViewControllers.last === pushedViewController)

    navigationController.pushViewController(nextViewController, animated: false)
    #expect(navigationController.topViewController === nextViewController)
}

private final class TestViewController: NSViewController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    }
}

private final class HorizontalScrollRootViewController: NSViewController {
    override func loadView() {
        view = makeHorizontalTestScrollView(visibleWidth: 100, documentWidth: 300)
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

@MainActor
private func firstSwipeTrackingResponder(startingAt responder: NSResponder, axis: NSEvent.GestureAxis) -> NSResponder? {
    var currentResponder: NSResponder? = responder

    while let responder = currentResponder {
        if responder.wantsScrollEventsForSwipeTracking(on: axis) {
            return responder
        }

        currentResponder = unsafe responder.nextResponder
    }

    return nil
}

@MainActor
private func makeHorizontalTestScrollView(visibleWidth: CGFloat, documentWidth: CGFloat) -> NSScrollView {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: visibleWidth, height: 80))
    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = false
    scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: documentWidth, height: 80))
    scrollView.layoutSubtreeIfNeeded()
    return scrollView
}

private func isApproximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 0.001) -> Bool {
    abs(lhs - rhs) <= tolerance
}

private func isBack(_ direction: NavigationStackDirection?) -> Bool {
    guard let direction else {
        return false
    }

    if case .back = direction {
        return true
    }

    return false
}

private func isForward(_ direction: NavigationStackDirection?) -> Bool {
    guard let direction else {
        return false
    }

    if case .forward = direction {
        return true
    }

    return false
}

private func makeScrollWheelEvent(deltaX: Int32, deltaY: Int32 = 0, phase: NSEvent.Phase = [], momentumPhase: NSEvent.Phase = []) -> NSEvent {
    let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: deltaY, wheel2: deltaX, wheel3: 0)!
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: cgScrollPhaseValue(for: phase))
    event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: cgScrollPhaseValue(for: momentumPhase))
    return NSEvent(cgEvent: event)!
}

private func cgScrollPhaseValue(for phase: NSEvent.Phase) -> Int64 {
    if phase.contains(.mayBegin) {
        return 128
    }

    if phase.contains(.began) {
        return 1
    }

    if phase.contains(.changed) {
        return 2
    }

    if phase.contains(.ended) {
        return 4
    }

    if phase.contains(.cancelled) {
        return 8
    }

    return 0
}
