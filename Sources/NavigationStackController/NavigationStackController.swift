import AppKit

/// The operation that caused a navigation stack controller to show a view controller.
public enum NavigationStackOperation: Equatable, Sendable {
    /// The stack was replaced with a new set of view controllers.
    case set

    /// A new view controller was pushed on top of the stack.
    case push

    /// The stack moved backward in its history.
    case back

    /// The stack moved forward in its history.
    case forward
}

enum NavigationStackDirection: Equatable {
    case push
    case back
    case forward
}

/// Receives notifications when a navigation stack controller is about to show, or has shown, a view controller.
@MainActor
public protocol NavigationStackControllerDelegate: AnyObject {
    /// Tells the delegate that the navigation stack controller is about to show a view controller.
    ///
    /// - Parameters:
    ///   - controller: The navigation stack controller sending the notification.
    ///   - viewController: The view controller that is about to become visible.
    ///   - operation: The navigation operation that caused the change.
    ///   - animated: A Boolean value indicating whether the change is animated.
    func navigationStackController(_ controller: NavigationStackController, willShow viewController: NSViewController, operation: NavigationStackOperation, animated: Bool)

    /// Tells the delegate that the navigation stack controller has shown a view controller.
    ///
    /// - Parameters:
    ///   - controller: The navigation stack controller sending the notification.
    ///   - viewController: The view controller that became visible.
    ///   - operation: The navigation operation that caused the change.
    ///   - animated: A Boolean value indicating whether the change was animated.
    func navigationStackController(_ controller: NavigationStackController, didShow viewController: NSViewController, operation: NavigationStackOperation, animated: Bool)
}

public extension NavigationStackControllerDelegate {
    func navigationStackController(_ controller: NavigationStackController, willShow viewController: NSViewController, operation: NavigationStackOperation, animated: Bool) { }
    func navigationStackController(_ controller: NavigationStackController, didShow viewController: NSViewController, operation: NavigationStackOperation, animated: Bool) { }
}

/// An AppKit container view controller that manages a stack of child view controllers.
///
/// `NavigationStackController` provides a browser-style history model for `NSViewController` instances.
/// Pushing a new view controller appends it to the back stack and clears forward history. Calling
/// ``goBack(animated:)`` and ``goForward(animated:)`` moves view controllers between the back and forward
/// stacks.
///
/// The controller owns AppKit child containment for every view controller in the stack, but installs only
/// the currently visible view controller's view in its content view when no transition is active.
@MainActor
public final class NavigationStackController: NSViewController {
    /// The delegate object that receives navigation display notifications.
    public weak var delegate: NavigationStackControllerDelegate?

    /// The current back stack, including the root view controller and the top view controller.
    ///
    /// The last element is the current top view controller.
    public private(set) var viewControllers: [NSViewController] = []

    /// The forward-history list.
    ///
    /// The first element is the next view controller that ``goForward(animated:)`` restores.
    public var forwardViewControllers: [NSViewController] {
        Array(forwardViewControllerStack.reversed())
    }

    /// A Boolean value that determines whether horizontal trackpad swipes can navigate back and forward.
    public var allowsBackForwardNavigationGestures = true

    /// The swipe distance, in points, used as the baseline commit threshold for interactive navigation.
    ///
    /// The effective threshold is also capped by ``maximumSwipeCompletionThreshold``.
    public var swipeCompletionDistance: CGFloat = 187.5

    /// The maximum swipe progress required to commit an interactive navigation.
    ///
    /// This value is a fraction of the container width. For example, `0.5` means a swipe never requires
    /// more than half of the container width to commit.
    public var maximumSwipeCompletionThreshold: CGFloat = 0.5

    /// The duration, in seconds, used to project swipe velocity when deciding whether to commit or cancel.
    public var swipeKineticProjectionDuration: TimeInterval = 0.3

    /// The minimum duration, in seconds, for the animation that finishes an interactive swipe.
    public var minimumSwipeAnimationDuration: TimeInterval = 0.1

    /// The maximum duration, in seconds, for the animation that finishes an interactive swipe.
    public var maximumSwipeAnimationDuration: TimeInterval = 0.4

    /// The duration, in seconds, for noninteractive push, back, and forward transitions.
    public var transitionDuration: TimeInterval = 0.25

    /// The fraction of the container width used for the background view's parallax movement.
    ///
    /// Set this value to `0` to disable parallax during transitions.
    public var parallaxFactor: CGFloat = 0.28

    /// The view controller at the top of the back stack.
    public var topViewController: NSViewController? {
        viewControllers.last
    }

    /// The view controller currently considered visible.
    ///
    /// During an active transition, this returns the transition's visible endpoint. Otherwise, it returns
    /// ``topViewController``.
    public var visibleViewController: NSViewController? {
        activeTransition?.visibleViewController ?? topViewController
    }

    /// A Boolean value that indicates whether the controller can move backward in history.
    public var canGoBack: Bool {
        viewControllers.count > 1
    }

    /// A Boolean value that indicates whether the controller can move forward in history.
    public var canGoForward: Bool {
        !forwardViewControllerStack.isEmpty
    }

    private var containerView: NavigationStackContainerView {
        view as! NavigationStackContainerView
    }

    private var forwardViewControllerStack: [NSViewController] = []
    private var activeTransition: Transition?
    private var isNotifyingWillShow = false
    private struct EventMonitorToken: @unchecked Sendable {
        let value: Any
    }

    private struct EventBox: @unchecked Sendable {
        let value: NSEvent
    }

    private var gestureEventMonitor: EventMonitorToken?
    private lazy var viewGestureController = NavigationViewGestureController(navigationController: self)

    var isGestureEventMonitorInstalled: Bool {
        gestureEventMonitor != nil
    }

    private var canStartNavigation: Bool {
        activeTransition == nil && !isNotifyingWillShow
    }

    /// Creates a navigation stack controller with a root view controller.
    ///
    /// - Parameter rootViewController: The first view controller in the navigation stack.
    public convenience init(rootViewController: NSViewController) {
        self.init()
        setViewControllers([rootViewController], animated: false)
    }

    /// Creates an empty navigation stack controller.
    ///
    /// Use ``setViewControllers(_:animated:)`` before presenting the controller, or use
    /// ``init(rootViewController:)`` to create the controller with a root view controller.
    public override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    deinit {
        if let gestureEventMonitor {
            NSEvent.removeMonitor(gestureEventMonitor.value)
        }
    }

    /// Creates a navigation stack controller from an archive.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Creates the container view used to host the visible child view controller.
    public override func loadView() {
        let view = NavigationStackContainerView()
        view.navigationController = self
        self.view = view
    }

    /// Installs the current top view controller after the controller's view has loaded.
    public override func viewDidLoad() {
        super.viewDidLoad()
        showTopViewController(operation: .set, animated: false)
    }

    /// Lays out the visible view controller or active transition views.
    public override func viewDidLayout() {
        super.viewDidLayout()
        layoutContentViews()
    }

    public override func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
        let wants = shouldForwardScrollEventsForSwipeTracking(on: axis)
        return wants
    }

    public override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool {
        let wants = shouldForwardScrollEventsForSwipeTracking(on: axis)
        return wants
    }

    @objc(_tryToSwipeWithEvent:ignoringPinnedState:)
    func _tryToSwipe(with event: NSEvent, ignoringPinnedState: Bool) -> Bool {
        let handled = handleScrollWheel(event, ignoringHorizontalScrollViews: ignoringPinnedState)
        return handled
    }

    /// Replaces the current stack with a new set of view controllers.
    ///
    /// Calling this method clears forward history. The array must contain at least one view controller.
    /// Calls made during an active transition, or with duplicate view controller instances, are ignored.
    ///
    /// - Parameters:
    ///   - newViewControllers: The new stack of view controllers. The last element becomes the top view controller.
    ///   - animated: A Boolean value indicating whether to animate from the old top view controller to the new one.
    public func setViewControllers(_ newViewControllers: [NSViewController], animated: Bool) {
        precondition(!newViewControllers.isEmpty, "NavigationStackController requires at least one view controller.")

        guard canStartNavigation else {
            return
        }

        guard Self.hasUniqueViewControllerInstances(newViewControllers) else {
            return
        }

        let oldTopViewController = topViewController
        let newTopViewController = newViewControllers.last

        forwardViewControllerStack.removeAll()
        viewControllers = newViewControllers

        guard isViewLoaded else {
            reconcileChildViewControllers(keeping: newViewControllers)
            return
        }

        if animated, let fromViewController = oldTopViewController, let toViewController = newTopViewController, fromViewController !== toViewController {
            var transitionViewControllers = newViewControllers
            if !transitionViewControllers.contains(where: { $0 === fromViewController }) {
                transitionViewControllers.append(fromViewController)
            }
            reconcileChildViewControllers(keeping: transitionViewControllers)
            runTransition(from: fromViewController, to: toViewController, direction: .push, operation: .set, animated: true) { [weak self] in
                self?.reconcileChildViewControllers(keeping: newViewControllers)
            }
            return
        }

        reconcileChildViewControllers(keeping: newViewControllers)
        showTopViewController(operation: .set, animated: false)
    }

    /// Pushes a view controller onto the top of the stack.
    ///
    /// Pushing a view controller clears forward history. Calls made during an active transition, or with a
    /// view controller already in back or forward history, are ignored.
    ///
    /// - Parameters:
    ///   - viewController: The view controller to push.
    ///   - animated: A Boolean value indicating whether to animate the transition.
    public func pushViewController(_ viewController: NSViewController, animated: Bool) {
        guard canStartNavigation else {
            return
        }

        guard !containsViewControllerInstance(viewController) else {
            return
        }

        let fromViewController = topViewController
        forwardViewControllerStack.removeAll()
        viewControllers.append(viewController)
        reconcileChildViewControllers(keeping: viewControllers)

        guard isViewLoaded else {
            return
        }

        guard let fromViewController, fromViewController !== viewController else {
            showTopViewController(operation: .push, animated: false)
            return
        }

        runTransition(from: fromViewController, to: viewController, direction: .push, operation: .push, animated: animated) { }
    }

    /// Pops the top view controller by moving backward in history.
    ///
    /// This method is an alias for ``goBack(animated:)``.
    ///
    /// - Parameter animated: A Boolean value indicating whether to animate the transition.
    /// - Returns: The view controller removed from the top of the stack, or `nil` if the controller cannot go back.
    @discardableResult
    public func popViewController(animated: Bool) -> NSViewController? {
        goBack(animated: animated)
    }

    /// Pops all view controllers above the root view controller.
    ///
    /// The popped view controllers are moved into forward history so they can be restored with
    /// ``goForward(animated:)``.
    ///
    /// - Parameter animated: A Boolean value indicating whether to animate the transition to the root view controller.
    /// - Returns: The popped view controllers, in their original stack order.
    @discardableResult
    public func popToRootViewController(animated: Bool) -> [NSViewController] {
        guard viewControllers.count > 1, canStartNavigation else {
            return []
        }

        let poppedViewControllers = Array(viewControllers.dropFirst())
        let rootViewController = viewControllers[0]
        let fromViewController = viewControllers.last

        forwardViewControllerStack.append(contentsOf: poppedViewControllers.reversed())
        viewControllers = [rootViewController]

        guard isViewLoaded else {
            return poppedViewControllers
        }

        guard animated, let fromViewController else {
            showTopViewController(operation: .back, animated: false)
            return poppedViewControllers
        }

        runTransition(from: fromViewController, to: rootViewController, direction: .back, operation: .back, animated: true) { }
        return poppedViewControllers
    }

    /// Moves backward to the previous view controller in history.
    ///
    /// The current top view controller is moved into forward history.
    ///
    /// - Parameter animated: A Boolean value indicating whether to animate the transition.
    /// - Returns: The view controller that was moved into forward history, or `nil` if the controller cannot go back.
    @discardableResult
    public func goBack(animated: Bool) -> NSViewController? {
        guard canGoBack, canStartNavigation else {
            return nil
        }

        let outgoingViewController = viewControllers[viewControllers.count - 1]
        let incomingViewController = viewControllers[viewControllers.count - 2]

        let commit: @MainActor @Sendable () -> Void = { [weak self] in
            self?.commitBackTransition(from: outgoingViewController, to: incomingViewController)
        }

        guard isViewLoaded else {
            commit()
            return outgoingViewController
        }

        guard animated else {
            commit()
            showTopViewController(operation: .back, animated: false)
            return outgoingViewController
        }

        commit()
        runTransition(from: outgoingViewController, to: incomingViewController, direction: .back, operation: .back, animated: true) { }
        return outgoingViewController
    }

    /// Moves forward to the next view controller in forward history.
    ///
    /// The restored view controller is appended to the back stack and becomes the top view controller.
    ///
    /// - Parameter animated: A Boolean value indicating whether to animate the transition.
    /// - Returns: The restored view controller, or `nil` if the controller cannot go forward.
    @discardableResult
    public func goForward(animated: Bool) -> NSViewController? {
        guard canGoForward, canStartNavigation else {
            return nil
        }

        let outgoingViewController = viewControllers[viewControllers.count - 1]
        let incomingViewController = forwardViewControllerStack[forwardViewControllerStack.count - 1]

        let commit: @MainActor @Sendable () -> Void = { [weak self] in
            self?.commitForwardTransition(from: outgoingViewController, to: incomingViewController)
        }

        guard isViewLoaded else {
            commit()
            return incomingViewController
        }

        guard animated else {
            commit()
            showTopViewController(operation: .forward, animated: false)
            return incomingViewController
        }

        commit()
        runTransition(from: outgoingViewController, to: incomingViewController, direction: .forward, operation: .forward, animated: true) { }
        return incomingViewController
    }

    fileprivate func handleScrollWheel(_ event: NSEvent, ignoringHorizontalScrollViews: Bool = false) -> Bool {
        let handled = viewGestureController.handleScrollWheel(event, ignoringHorizontalScrollViews: ignoringHorizontalScrollViews)
        updateGestureEventMonitorState()
        return handled
    }

    func finishActiveSwipeGesture(cancelled: Bool) -> Bool {
        let handled = viewGestureController.finishActiveSwipeGesture(cancelled: cancelled)
        updateGestureEventMonitorState()
        return handled
    }

    func shouldDeferSwipeTrackingToHorizontalScrollView(for event: NSEvent) -> Bool {
        let localPoint = containerView.convert(event.locationInWindow, from: nil)
        let hitView = containerView.hitTest(localPoint)

        let shouldDefer = NavigationHorizontalScrollConflictResolver.canScrollHorizontally(
            from: hitView,
            inside: containerView,
            deltaX: event.scrollingDeltaX
        )
        return shouldDefer
    }

    fileprivate func shouldForwardScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
        viewGestureController.wantsScrollEventsForSwipeTracking(on: axis)
    }

    private func startGestureEventMonitorIfNeeded() {
        guard gestureEventMonitor == nil else {
            return
        }

        guard let monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .endGesture], handler: { [weak self] event in
            let eventBox = EventBox(value: event)
            let consumed = MainActor.assumeIsolated {
                guard let self else {
                    return false
                }

                return self.handleLocalGestureMonitorEvent(eventBox.value)
            }
            return consumed ? nil : event
        }) else {
            return
        }

        gestureEventMonitor = EventMonitorToken(value: monitor)
    }

    private func updateGestureEventMonitorState() {
        if viewGestureController.isTrackingSwipeGesture || activeTransition != nil {
            startGestureEventMonitorIfNeeded()
        } else {
            stopGestureEventMonitor()
        }
    }

    func handleLocalGestureMonitorEvent(_ event: NSEvent, requiringMatchingWindow: Bool = true) -> Bool {
        let currentWindow = unsafe view.window
        let currentWindowNumber = currentWindow?.windowNumber
        let matchesWindow = !requiringMatchingWindow
            || (event.window != nil && event.window === currentWindow)
            || (event.windowNumber != 0 && event.windowNumber == currentWindowNumber)

        switch event.type {
        case .scrollWheel:
            guard matchesWindow else {
                return false
            }

            let handled = handleScrollWheel(event, ignoringHorizontalScrollViews: true)
            return handled
        case .endGesture:
            guard matchesWindow else {
                return false
            }

            return finishActiveSwipeGesture(cancelled: false)
        default:
            return false
        }
    }

    private func stopGestureEventMonitor() {
        guard let gestureEventMonitor else {
            return
        }

        NSEvent.removeMonitor(gestureEventMonitor.value)
        self.gestureEventMonitor = nil
    }

    fileprivate func layoutContentViews() {
        if let activeTransition {
            activeTransition.layout(in: containerView.bounds, parallaxFactor: parallaxFactor, layoutDirection: view.userInterfaceLayoutDirection)
            return
        }

        guard let topView = topViewController?.view, containerView.subviews.contains(where: { $0 === topView }) else {
            return
        }

        topView.frame = containerView.bounds
    }
}

extension NavigationStackController {
    @MainActor
    final class Transition {
        let fromViewController: NSViewController
        let toViewController: NSViewController
        let direction: NavigationStackDirection
        let operation: NavigationStackOperation
        let backdropView = NavigationTransitionBackdropView()
        let fromTransitionView = NavigationTransitionContentView()
        let toTransitionView = NavigationTransitionContentView()
        var progress: CGFloat = 0
        var isAnimating = false

        var visibleViewController: NSViewController {
            progress >= 1 ? toViewController : fromViewController
        }

        private var fromAnimatedView: NSView {
            fromTransitionView.contentView == nil ? fromViewController.view : fromTransitionView
        }

        private var toAnimatedView: NSView {
            toTransitionView.contentView == nil ? toViewController.view : toTransitionView
        }

        init(from fromViewController: NSViewController, to toViewController: NSViewController, direction: NavigationStackDirection, operation: NavigationStackOperation) {
            self.fromViewController = fromViewController
            self.toViewController = toViewController
            self.direction = direction
            self.operation = operation
        }

        func layout(in bounds: NSRect, parallaxFactor: CGFloat, layoutDirection: NSUserInterfaceLayoutDirection) {
            guard !isAnimating else {
                return
            }

            apply(progress: progress, in: bounds, parallaxFactor: parallaxFactor, layoutDirection: layoutDirection, animated: false)
        }

        func apply(progress rawProgress: CGFloat, in bounds: NSRect, parallaxFactor: CGFloat, layoutDirection: NSUserInterfaceLayoutDirection, animated: Bool) {
            let progress = min(max(rawProgress, 0), 1)
            if !animated {
                self.progress = progress
            }

            let width = max(bounds.width, 1)
            let layoutSign: CGFloat = layoutDirection == .rightToLeft ? -1 : 1
            let fromView = fromAnimatedView
            let toView = toAnimatedView
            backdropView.frame = bounds
            var fromFrame = bounds
            var toFrame = bounds

            switch direction {
            case .push:
                fromFrame.origin.x = -layoutSign * width * parallaxFactor * progress
                toFrame.origin.x = layoutSign * width * (1 - progress)
            case .back:
                fromFrame.origin.x = layoutSign * width * progress
                toFrame.origin.x = -layoutSign * width * parallaxFactor * (1 - progress)
            case .forward:
                fromFrame.origin.x = -layoutSign * width * progress
                toFrame.origin.x = layoutSign * width * (1 - progress)
            }

            if animated {
                fromView.animator().frame = fromFrame
                toView.animator().frame = toFrame
            } else {
                fromView.frame = fromFrame
                toView.frame = toFrame
            }
        }
    }

    func reconcileChildViewControllers(keeping viewControllersToKeep: [NSViewController]) {
        let retainedIDs = Set(viewControllersToKeep.map { ObjectIdentifier($0) })

        for child in children where !retainedIDs.contains(ObjectIdentifier(child)) {
            child.removeFromParent()
        }

        for viewController in viewControllersToKeep {
            adopt(viewController)
        }
    }

    func adopt(_ viewController: NSViewController) {
        guard viewController.parent !== self else {
            return
        }

        viewController.removeFromParent()
        addChild(viewController)
    }

    func containsViewControllerInstance(_ viewController: NSViewController) -> Bool {
        viewControllers.contains { $0 === viewController } || forwardViewControllerStack.contains { $0 === viewController }
    }

    static func hasUniqueViewControllerInstances(_ viewControllers: [NSViewController]) -> Bool {
        var identifiers = Set<ObjectIdentifier>()

        for viewController in viewControllers {
            guard identifiers.insert(ObjectIdentifier(viewController)).inserted else {
                return false
            }
        }

        return true
    }

    func showTopViewController(operation: NavigationStackOperation, animated: Bool) {
        guard let topViewController else {
            return
        }

        notifyWillShow(topViewController, operation: operation, animated: animated)

        installOnly(topViewController)

        delegate?.navigationStackController(self, didShow: topViewController, operation: operation, animated: animated)
    }

    func installOnly(_ viewController: NSViewController) {
        for subview in containerView.subviews where subview !== viewController.view {
            subview.removeFromSuperview()
        }

        let contentView = viewController.view
        contentView.removeFromSuperview()
        contentView.frame = containerView.bounds
        contentView.autoresizingMask = [.width, .height]
        contentView.wantsLayer = true
        containerView.addSubview(contentView)
    }

    func notifyWillShow(_ viewController: NSViewController, operation: NavigationStackOperation, animated: Bool) {
        isNotifyingWillShow = true
        defer { isNotifyingWillShow = false }
        delegate?.navigationStackController(self, willShow: viewController, operation: operation, animated: animated)
    }

    func prepareTransition(_ transition: Transition) {
        let fromView = transition.fromViewController.view
        let toView = transition.toViewController.view

        fromView.removeFromSuperview()
        toView.removeFromSuperview()

        fromView.autoresizingMask = [.width, .height]
        toView.autoresizingMask = [.width, .height]
        fromView.wantsLayer = true
        toView.wantsLayer = true
        transition.fromTransitionView.installContentView(fromView)
        transition.toTransitionView.installContentView(toView)

        let fromTransitionView = transition.fromTransitionView
        let toTransitionView = transition.toTransitionView

        switch transition.direction {
        case .push, .forward:
            containerView.addSubview(fromTransitionView)
            containerView.addSubview(toTransitionView, positioned: .above, relativeTo: fromTransitionView)
        case .back:
            transition.backdropView.backgroundColor = transitionBackdropColor(matching: toView)
            containerView.addSubview(transition.backdropView)
            containerView.addSubview(toTransitionView)
            containerView.addSubview(fromTransitionView, positioned: .above, relativeTo: toTransitionView)
        }

        transition.apply(progress: 0, in: containerView.bounds, parallaxFactor: parallaxFactor, layoutDirection: view.userInterfaceLayoutDirection, animated: false)
        primeTransitionViewForDisplay(fromTransitionView)
        primeTransitionViewForDisplay(toTransitionView)
    }

    func primeTransitionViewForDisplay(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
    }

    func transitionBackdropColor(matching view: NSView) -> NSColor {
        if let scrollView = view as? NSScrollView {
            if scrollView.drawsBackground {
                return scrollView.backgroundColor
            }

            if scrollView.contentView.drawsBackground {
                return scrollView.contentView.backgroundColor
            }
        }

        if let backgroundColor = view.layer?.backgroundColor, let color = NSColor(cgColor: backgroundColor), color.alphaComponent > 0 {
            return color
        }

        return .windowBackgroundColor
    }

    func runTransition(from fromViewController: NSViewController, to toViewController: NSViewController, direction: NavigationStackDirection, operation: NavigationStackOperation, animated: Bool, commit: @escaping @MainActor @Sendable () -> Void) {
        let transition = Transition(from: fromViewController, to: toViewController, direction: direction, operation: operation)
        activeTransition = transition
        notifyWillShow(toViewController, operation: operation, animated: animated)
        prepareTransition(transition)

        guard animated else {
            transition.apply(progress: 1, in: containerView.bounds, parallaxFactor: parallaxFactor, layoutDirection: view.userInterfaceLayoutDirection, animated: false)
            finishTransition(transition, committed: true, commit: commit, animated: false)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = transitionDuration
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            transition.isAnimating = true
            transition.apply(progress: 1, in: containerView.bounds, parallaxFactor: parallaxFactor, layoutDirection: view.userInterfaceLayoutDirection, animated: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                transition.isAnimating = false
                self.finishTransition(transition, committed: true, commit: commit, animated: true)
            }
        }
    }

    func finishTransition(_ transition: Transition, committed: Bool, commit: @MainActor @Sendable () -> Void, animated: Bool) {
        if activeTransition === transition {
            activeTransition = nil
            stopGestureEventMonitor()
        }

        if committed {
            commit()
            installOnly(transition.toViewController)
            delegate?.navigationStackController(self, didShow: transition.toViewController, operation: transition.operation, animated: animated)
        } else {
            installOnly(transition.fromViewController)
            delegate?.navigationStackController(self, didShow: transition.fromViewController, operation: transition.operation, animated: animated)
        }
    }

    func canNavigateInteractively(in direction: NavigationStackDirection) -> Bool {
        switch direction {
        case .push:
            return false
        case .back:
            return canGoBack
        case .forward:
            return canGoForward
        }
    }

    func canBeginSwipeGesture(in direction: NavigationStackDirection) -> Bool {
        canStartNavigation && canNavigateInteractively(in: direction)
    }

    func commitBackTransition(from outgoingViewController: NSViewController, to incomingViewController: NSViewController) {
        guard viewControllers.count > 1, viewControllers.last === outgoingViewController, viewControllers[viewControllers.count - 2] === incomingViewController else {
            return
        }

        let removedViewController = viewControllers.removeLast()
        forwardViewControllerStack.append(removedViewController)
    }

    func commitForwardTransition(from outgoingViewController: NSViewController, to incomingViewController: NSViewController) {
        guard topViewController === outgoingViewController, forwardViewControllerStack.last === incomingViewController else {
            return
        }

        let restoredViewController = forwardViewControllerStack.removeLast()
        viewControllers.append(restoredViewController)
    }

    func commitStackMutation(for transition: Transition) {
        switch transition.direction {
        case .push:
            break
        case .back:
            commitBackTransition(from: transition.fromViewController, to: transition.toViewController)
        case .forward:
            commitForwardTransition(from: transition.fromViewController, to: transition.toViewController)
        }
    }

    func navigationDirection(forHorizontalDelta deltaX: CGFloat) -> NavigationStackDirection {
        let isLeftToRight = view.userInterfaceLayoutDirection == .leftToRight
        let wantsBack = isLeftToRight ? deltaX > 0 : deltaX < 0
        return wantsBack ? .back : .forward
    }

    var swipeDistance: CGFloat {
        max(containerView.bounds.width, 1)
    }

    func beginSwipeGesture(direction: NavigationStackDirection) -> Bool {
        guard canStartNavigation else {
            return false
        }

        let fromViewController: NSViewController
        let toViewController: NSViewController
        let operation: NavigationStackOperation

        switch direction {
        case .push:
            return false
        case .back:
            guard viewControllers.count > 1 else {
                return false
            }
            fromViewController = viewControllers[viewControllers.count - 1]
            toViewController = viewControllers[viewControllers.count - 2]
            operation = .back
        case .forward:
            guard let forwardViewController = forwardViewControllerStack.last, let topViewController else {
                return false
            }
            fromViewController = topViewController
            toViewController = forwardViewController
            operation = .forward
        }
        let transition = Transition(from: fromViewController, to: toViewController, direction: direction, operation: operation)
        activeTransition = transition
        startGestureEventMonitorIfNeeded()
        notifyWillShow(toViewController, operation: operation, animated: true)
        prepareTransition(transition)
        return true
    }

    func handleSwipeGesture(progress: CGFloat) {
        activeTransition?.apply(progress: progress, in: containerView.bounds, parallaxFactor: parallaxFactor, layoutDirection: view.userInterfaceLayoutDirection, animated: false)
    }

    func endSwipeGesture(committed: Bool, duration: TimeInterval, completion: @escaping @MainActor () -> Void) {
        guard let transition = activeTransition else {
            completion()
            return
        }

        let targetProgress: CGFloat = committed ? 1 : 0
        guard duration > 0 else {
            transition.apply(progress: targetProgress, in: containerView.bounds, parallaxFactor: parallaxFactor, layoutDirection: view.userInterfaceLayoutDirection, animated: false)
            completeSwipeTransitionIfCurrent(transition, committed: committed, animated: false, completion: completion)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(name: committed ? .easeOut : .easeInEaseOut)
            transition.isAnimating = true
            transition.apply(progress: targetProgress, in: containerView.bounds, parallaxFactor: parallaxFactor, layoutDirection: view.userInterfaceLayoutDirection, animated: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }

                transition.isAnimating = false
                self.completeSwipeTransitionIfCurrent(transition, committed: committed, animated: true, completion: completion)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                transition.isAnimating = false
                self?.completeSwipeTransitionIfCurrent(transition, committed: committed, animated: true, completion: completion)
            }
        }
    }

    private func completeSwipeTransitionIfCurrent(_ transition: Transition, committed: Bool, animated: Bool, completion: @escaping @MainActor () -> Void) {
        guard activeTransition === transition else {
            return
        }

        finishTransition(transition, committed: committed, commit: {
            commitStackMutation(for: transition)
        }, animated: animated)
        completion()
    }

}

@MainActor
struct NavigationHorizontalScrollConflictResolver {
    static func canScrollHorizontally(from hitView: NSView?, inside boundaryView: NSView, deltaX: CGFloat) -> Bool {
        guard deltaX != 0 else {
            return false
        }

        var currentView = hitView
        while let view = currentView {
            if let scrollView = view as? NSScrollView {
                let canScroll = canScrollHorizontally(scrollView, deltaX: deltaX)
                if canScroll {
                    return true
                }
            }

            if view === boundaryView {
                return false
            }

            currentView = unsafe view.superview
        }

        return false
    }

    static func canScrollHorizontally(_ scrollView: NSScrollView, deltaX: CGFloat) -> Bool {
        guard let documentView = scrollView.documentView else {
            return false
        }

        let visibleRect = scrollView.contentView.documentVisibleRect
        let documentBounds = documentView.bounds
        let minimumX = documentBounds.minX
        let maximumX = max(documentBounds.maxX - visibleRect.width, minimumX)
        let currentX = visibleRect.minX
        let tolerance: CGFloat = 0.5

        let canScroll = if deltaX > 0 {
            currentX > minimumX + tolerance
        } else {
            currentX < maximumX - tolerance
        }
        return canScroll
    }
}

private final class NavigationStackContainerView: NSView {
    weak var navigationController: NavigationStackController?

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureTouchTracking()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTouchTracking()
    }

    private func configureTouchTracking() {
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = true
    }

    override func layout() {
        super.layout()
        navigationController?.layoutContentViews()
    }

    override func scrollWheel(with event: NSEvent) {
        if navigationController?.handleScrollWheel(event) == true {
            return
        }
        super.scrollWheel(with: event)
    }

    override func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
        let wants = navigationController?.shouldForwardScrollEventsForSwipeTracking(on: axis) ?? false
        return wants
    }

    override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool {
        let wants = navigationController?.shouldForwardScrollEventsForSwipeTracking(on: axis) ?? false
        return wants
    }

    override func endGesture(with event: NSEvent) {
        if navigationController?.finishActiveSwipeGesture(cancelled: false) == true {
            return
        }

        super.endGesture(with: event)
    }

    override func touchesEnded(with event: NSEvent) {
        if navigationController?.finishActiveSwipeGesture(cancelled: false) == true {
            return
        }

        super.touchesEnded(with: event)
    }

    override func touchesCancelled(with event: NSEvent) {
        if navigationController?.finishActiveSwipeGesture(cancelled: true) == true {
            return
        }

        super.touchesCancelled(with: event)
    }

    @objc(_tryToSwipeWithEvent:ignoringPinnedState:)
    func _tryToSwipe(with event: NSEvent, ignoringPinnedState: Bool) -> Bool {
        let handled = navigationController?.handleScrollWheel(event, ignoringHorizontalScrollViews: ignoringPinnedState) ?? false
        return handled
    }
}

final class NavigationTransitionBackdropView: NSView {
    var backgroundColor: NSColor = .windowBackgroundColor {
        didSet {
            layer?.backgroundColor = backgroundColor.cgColor
            needsDisplay = true
        }
    }

    override var isOpaque: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    private func configureLayer() {
        wantsLayer = true
        layer?.backgroundColor = backgroundColor.cgColor
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        dirtyRect.fill()
    }
}

final class NavigationTransitionContentView: NSView {
    private(set) var contentView: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    func installContentView(_ view: NSView) {
        contentView?.removeFromSuperview()
        contentView = view
        view.removeFromSuperview()
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }

    override func layout() {
        super.layout()
        contentView?.frame = bounds
    }

    private func configureLayer() {
        wantsLayer = true
        layer?.masksToBounds = true
    }
}
