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

enum NavigationStackDirection {
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
    private lazy var viewGestureController = NavigationViewGestureController(navigationController: self)

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

    /// Replaces the current stack with a new set of view controllers.
    ///
    /// Calling this method clears forward history. The array must contain at least one view controller.
    /// Calls made during an active transition are ignored.
    ///
    /// - Parameters:
    ///   - newViewControllers: The new stack of view controllers. The last element becomes the top view controller.
    ///   - animated: A Boolean value indicating whether to animate from the old top view controller to the new one.
    public func setViewControllers(_ newViewControllers: [NSViewController], animated: Bool) {
        precondition(!newViewControllers.isEmpty, "NavigationStackController requires at least one view controller.")

        guard activeTransition == nil else {
            return
        }

        let oldTopViewController = topViewController
        let newTopViewController = newViewControllers.last

        forwardViewControllerStack.removeAll()
        viewControllers = newViewControllers
        reconcileChildViewControllers(keeping: newViewControllers)

        guard isViewLoaded else {
            return
        }

        if animated, let fromViewController = oldTopViewController, let toViewController = newTopViewController, fromViewController !== toViewController {
            runTransition(from: fromViewController, to: toViewController, direction: .push, operation: .set, animated: true) { }
            return
        }

        showTopViewController(operation: .set, animated: false)
    }

    /// Pushes a view controller onto the top of the stack.
    ///
    /// Pushing a view controller clears forward history. Calls made during an active transition are ignored.
    ///
    /// - Parameters:
    ///   - viewController: The view controller to push.
    ///   - animated: A Boolean value indicating whether to animate the transition.
    public func pushViewController(_ viewController: NSViewController, animated: Bool) {
        guard activeTransition == nil else {
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
        guard viewControllers.count > 1, activeTransition == nil else {
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
        guard canGoBack, activeTransition == nil else {
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

        runTransition(from: outgoingViewController, to: incomingViewController, direction: .back, operation: .back, animated: true, commit: commit)
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
        guard canGoForward, activeTransition == nil else {
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

        runTransition(from: outgoingViewController, to: incomingViewController, direction: .forward, operation: .forward, animated: true, commit: commit)
        return incomingViewController
    }

    fileprivate func handleScrollWheel(_ event: NSEvent) -> Bool {
        viewGestureController.handleScrollWheel(event)
    }

    fileprivate func shouldForwardScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
        viewGestureController.wantsScrollEventsForSwipeTracking(on: axis)
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
        var progress: CGFloat = 0

        var visibleViewController: NSViewController {
            progress >= 1 ? toViewController : fromViewController
        }

        init(from fromViewController: NSViewController, to toViewController: NSViewController, direction: NavigationStackDirection, operation: NavigationStackOperation) {
            self.fromViewController = fromViewController
            self.toViewController = toViewController
            self.direction = direction
            self.operation = operation
        }

        func layout(in bounds: NSRect, parallaxFactor: CGFloat, layoutDirection: NSUserInterfaceLayoutDirection) {
            apply(progress: progress, in: bounds, parallaxFactor: parallaxFactor, layoutDirection: layoutDirection, animated: false)
        }

        func apply(progress rawProgress: CGFloat, in bounds: NSRect, parallaxFactor: CGFloat, layoutDirection: NSUserInterfaceLayoutDirection, animated: Bool) {
            progress = min(max(rawProgress, 0), 1)

            let width = max(bounds.width, 1)
            let layoutSign: CGFloat = layoutDirection == .rightToLeft ? -1 : 1
            let fromView = fromViewController.view
            let toView = toViewController.view
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

    func showTopViewController(operation: NavigationStackOperation, animated: Bool) {
        guard let topViewController else {
            return
        }

        delegate?.navigationStackController(self, willShow: topViewController, operation: operation, animated: animated)

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

    func prepareTransition(_ transition: Transition) {
        let fromView = transition.fromViewController.view
        let toView = transition.toViewController.view

        fromView.removeFromSuperview()
        toView.removeFromSuperview()

        fromView.autoresizingMask = [.width, .height]
        toView.autoresizingMask = [.width, .height]
        fromView.wantsLayer = true
        toView.wantsLayer = true

        switch transition.direction {
        case .push, .forward:
            containerView.addSubview(fromView)
            containerView.addSubview(toView, positioned: .above, relativeTo: fromView)
        case .back:
            containerView.addSubview(toView)
            containerView.addSubview(fromView, positioned: .above, relativeTo: toView)
        }

        transition.apply(progress: 0, in: containerView.bounds, parallaxFactor: parallaxFactor, layoutDirection: view.userInterfaceLayoutDirection, animated: false)
    }

    func runTransition(from fromViewController: NSViewController, to toViewController: NSViewController, direction: NavigationStackDirection, operation: NavigationStackOperation, animated: Bool, commit: @escaping @MainActor @Sendable () -> Void) {
        delegate?.navigationStackController(self, willShow: toViewController, operation: operation, animated: animated)

        let transition = Transition(from: fromViewController, to: toViewController, direction: direction, operation: operation)
        activeTransition = transition
        prepareTransition(transition)

        guard animated else {
            transition.apply(progress: 1, in: containerView.bounds, parallaxFactor: parallaxFactor, layoutDirection: view.userInterfaceLayoutDirection, animated: false)
            finishTransition(transition, committed: true, commit: commit, animated: false)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = transitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            transition.apply(progress: 1, in: containerView.bounds, parallaxFactor: parallaxFactor, layoutDirection: view.userInterfaceLayoutDirection, animated: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                self.finishTransition(transition, committed: true, commit: commit, animated: true)
            }
        }
    }

    func finishTransition(_ transition: Transition, committed: Bool, commit: @MainActor @Sendable () -> Void, animated: Bool) {
        if activeTransition === transition {
            activeTransition = nil
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
        activeTransition == nil && canNavigateInteractively(in: direction)
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
        guard activeTransition == nil else {
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

        delegate?.navigationStackController(self, willShow: toViewController, operation: operation, animated: true)

        let transition = Transition(from: fromViewController, to: toViewController, direction: direction, operation: operation)
        activeTransition = transition
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

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: committed ? .easeOut : .easeInEaseOut)
            transition.apply(progress: targetProgress, in: containerView.bounds, parallaxFactor: parallaxFactor, layoutDirection: view.userInterfaceLayoutDirection, animated: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }

                self.finishTransition(transition, committed: committed, commit: {
                    self.commitStackMutation(for: transition)
                }, animated: true)
                completion()
            }
        }
    }
}

private final class NavigationStackContainerView: NSView {
    weak var navigationController: NavigationStackController?

    override var isFlipped: Bool {
        true
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
        navigationController?.shouldForwardScrollEventsForSwipeTracking(on: axis) ?? false
    }

    override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool {
        navigationController?.shouldForwardScrollEventsForSwipeTracking(on: axis) ?? false
    }
}
