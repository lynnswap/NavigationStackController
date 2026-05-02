import AppKit

public enum NavigationStackOperation: Equatable, Sendable {
    case set
    case push
    case back
    case forward
}

@MainActor
public protocol NavigationStackControllerDelegate: AnyObject {
    func navigationStackController(_ controller: NavigationStackController, willShow viewController: NSViewController, operation: NavigationStackOperation, animated: Bool)
    func navigationStackController(_ controller: NavigationStackController, didShow viewController: NSViewController, operation: NavigationStackOperation, animated: Bool)
}

public extension NavigationStackControllerDelegate {
    func navigationStackController(_ controller: NavigationStackController, willShow viewController: NSViewController, operation: NavigationStackOperation, animated: Bool) { }
    func navigationStackController(_ controller: NavigationStackController, didShow viewController: NSViewController, operation: NavigationStackOperation, animated: Bool) { }
}

@MainActor
public final class NavigationStackController: NSViewController {
    public weak var delegate: NavigationStackControllerDelegate?

    public private(set) var viewControllers: [NSViewController] = []
    public private(set) var forwardViewControllers: [NSViewController] = []

    public var allowsBackForwardNavigationGestures = true
    public var transitionDuration: TimeInterval = 0.25
    public var interactiveCompletionThreshold: CGFloat = 0.5
    public var parallaxFactor: CGFloat = 0.28

    public var topViewController: NSViewController? {
        viewControllers.last
    }

    public var visibleViewController: NSViewController? {
        activeTransition?.visibleViewController ?? topViewController
    }

    public var canGoBack: Bool {
        viewControllers.count > 1
    }

    public var canGoForward: Bool {
        !forwardViewControllers.isEmpty
    }

    private var containerView: NavigationStackContainerView {
        view as! NavigationStackContainerView
    }

    private var activeTransition: Transition?
    private var finishingInteractiveSwipe = false

    public convenience init(rootViewController: NSViewController) {
        self.init()
        setViewControllers([rootViewController], animated: false)
    }

    public override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override func loadView() {
        let view = NavigationStackContainerView()
        view.navigationController = self
        self.view = view
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        showTopViewController(operation: .set, animated: false)
    }

    public override func viewDidLayout() {
        super.viewDidLayout()
        layoutContentViews()
    }

    public func setViewControllers(_ newViewControllers: [NSViewController], animated: Bool) {
        precondition(!newViewControllers.isEmpty, "NavigationStackController requires at least one view controller.")

        guard activeTransition == nil else {
            return
        }

        let oldTopViewController = topViewController
        let newTopViewController = newViewControllers.last

        forwardViewControllers.removeAll()
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

    public func pushViewController(_ viewController: NSViewController, animated: Bool) {
        guard activeTransition == nil else {
            return
        }

        let fromViewController = topViewController
        forwardViewControllers.removeAll()
        adopt(viewController)
        viewControllers.append(viewController)

        guard isViewLoaded else {
            return
        }

        guard let fromViewController, fromViewController !== viewController else {
            showTopViewController(operation: .push, animated: false)
            return
        }

        runTransition(from: fromViewController, to: viewController, direction: .push, operation: .push, animated: animated) { }
    }

    @discardableResult
    public func popViewController(animated: Bool) -> NSViewController? {
        goBack(animated: animated)
    }

    @discardableResult
    public func popToRootViewController(animated: Bool) -> [NSViewController] {
        guard viewControllers.count > 1, activeTransition == nil else {
            return []
        }

        let poppedViewControllers = Array(viewControllers.dropFirst())
        let rootViewController = viewControllers[0]
        let fromViewController = viewControllers.last

        forwardViewControllers.append(contentsOf: poppedViewControllers.reversed())
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

    @discardableResult
    public func goForward(animated: Bool) -> NSViewController? {
        guard canGoForward, activeTransition == nil else {
            return nil
        }

        let outgoingViewController = viewControllers[viewControllers.count - 1]
        let incomingViewController = forwardViewControllers[forwardViewControllers.count - 1]

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
        guard allowsBackForwardNavigationGestures, activeTransition == nil, event.hasPreciseScrollingDeltas, NSEvent.isSwipeTrackingFromScrollEventsEnabled else {
            return false
        }

        guard event.phase.contains(.began), abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else {
            return false
        }

        let direction = navigationDirection(forHorizontalDelta: event.scrollingDeltaX)
        guard canNavigateInteractively(in: direction) else {
            return false
        }

        trackSwipeEvent(event, direction: direction)
        return true
    }

    fileprivate func shouldForwardScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
        axis == .horizontal && allowsBackForwardNavigationGestures && (canGoBack || canGoForward)
    }

    fileprivate func layoutContentViews() {
        if let activeTransition {
            activeTransition.layout(in: containerView.bounds, parallaxFactor: parallaxFactor)
            return
        }

        guard let topView = topViewController?.view, topView.superview === containerView else {
            return
        }

        topView.frame = containerView.bounds
    }
}

private extension NavigationStackController {
    enum Direction {
        case push
        case back
        case forward
    }

    @MainActor
    final class Transition {
        let fromViewController: NSViewController
        let toViewController: NSViewController
        let direction: Direction
        let operation: NavigationStackOperation
        var progress: CGFloat = 0

        var visibleViewController: NSViewController {
            progress >= 1 ? toViewController : fromViewController
        }

        init(from fromViewController: NSViewController, to toViewController: NSViewController, direction: Direction, operation: NavigationStackOperation) {
            self.fromViewController = fromViewController
            self.toViewController = toViewController
            self.direction = direction
            self.operation = operation
        }

        func layout(in bounds: NSRect, parallaxFactor: CGFloat) {
            apply(progress: progress, in: bounds, parallaxFactor: parallaxFactor, animated: false)
        }

        func apply(progress rawProgress: CGFloat, in bounds: NSRect, parallaxFactor: CGFloat, animated: Bool) {
            progress = min(max(rawProgress, 0), 1)

            let width = max(bounds.width, 1)
            let fromView = fromViewController.view
            let toView = toViewController.view
            var fromFrame = bounds
            var toFrame = bounds

            switch direction {
            case .push:
                fromFrame.origin.x = -width * parallaxFactor * progress
                toFrame.origin.x = width * (1 - progress)
            case .back:
                fromFrame.origin.x = width * progress
                toFrame.origin.x = -width * parallaxFactor * (1 - progress)
            case .forward:
                fromFrame.origin.x = -width * progress
                toFrame.origin.x = width * (1 - progress)
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

        transition.apply(progress: 0, in: containerView.bounds, parallaxFactor: parallaxFactor, animated: false)
    }

    func runTransition(from fromViewController: NSViewController, to toViewController: NSViewController, direction: Direction, operation: NavigationStackOperation, animated: Bool, commit: @escaping @MainActor @Sendable () -> Void) {
        delegate?.navigationStackController(self, willShow: toViewController, operation: operation, animated: animated)

        let transition = Transition(from: fromViewController, to: toViewController, direction: direction, operation: operation)
        activeTransition = transition
        prepareTransition(transition)

        guard animated else {
            transition.apply(progress: 1, in: containerView.bounds, parallaxFactor: parallaxFactor, animated: false)
            finishTransition(transition, committed: true, commit: commit, animated: false)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = transitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            transition.apply(progress: 1, in: containerView.bounds, parallaxFactor: parallaxFactor, animated: true)
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

    func canNavigateInteractively(in direction: Direction) -> Bool {
        switch direction {
        case .push:
            return false
        case .back:
            return canGoBack
        case .forward:
            return canGoForward
        }
    }

    func commitBackTransition(from outgoingViewController: NSViewController, to incomingViewController: NSViewController) {
        guard viewControllers.count > 1, viewControllers.last === outgoingViewController, viewControllers[viewControllers.count - 2] === incomingViewController else {
            return
        }

        let removedViewController = viewControllers.removeLast()
        forwardViewControllers.append(removedViewController)
    }

    func commitForwardTransition(from outgoingViewController: NSViewController, to incomingViewController: NSViewController) {
        guard topViewController === outgoingViewController, forwardViewControllers.last === incomingViewController else {
            return
        }

        let restoredViewController = forwardViewControllers.removeLast()
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

    func navigationDirection(forHorizontalDelta deltaX: CGFloat) -> Direction {
        let isLeftToRight = view.userInterfaceLayoutDirection == .leftToRight
        let wantsBack = isLeftToRight ? deltaX > 0 : deltaX < 0
        return wantsBack ? .back : .forward
    }

    func progressSign(for direction: Direction) -> CGFloat {
        let isLeftToRight = view.userInterfaceLayoutDirection == .leftToRight

        switch direction {
        case .push:
            return 1
        case .back:
            return isLeftToRight ? 1 : -1
        case .forward:
            return isLeftToRight ? -1 : 1
        }
    }

    func trackSwipeEvent(_ event: NSEvent, direction: Direction) {
        let sign = progressSign(for: direction)
        let minProgress: CGFloat = sign < 0 ? -1 : 0
        let maxProgress: CGFloat = sign > 0 ? 1 : 0
        var latestProgress: CGFloat = 0
        var swipeWasCancelled = false
        var didCompleteSwipe = false

        event.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount], dampenAmountThresholdMin: minProgress, max: maxProgress) { [weak self] amount, phase, isComplete, stop in
            guard let self else {
                stop.pointee = true
                return
            }

            guard !didCompleteSwipe else {
                stop.pointee = true
                return
            }

            let progress = min(max(amount * sign, 0), 1)
            latestProgress = progress

            if phase.contains(.began), self.activeTransition == nil {
                self.beginInteractiveTransition(direction: direction)
            } else if self.activeTransition == nil, progress > 0 {
                self.beginInteractiveTransition(direction: direction)
            }

            self.activeTransition?.apply(progress: progress, in: self.containerView.bounds, parallaxFactor: self.parallaxFactor, animated: false)

            if phase.contains(.cancelled) {
                swipeWasCancelled = true
            }

            if isComplete {
                didCompleteSwipe = true
                stop.pointee = true

                let shouldCommit = !swipeWasCancelled && latestProgress >= self.interactiveCompletionThreshold
                self.completeInteractiveTransition(committed: shouldCommit)
            }
        }
    }

    func beginInteractiveTransition(direction: Direction) {
        guard activeTransition == nil else {
            return
        }

        let fromViewController: NSViewController
        let toViewController: NSViewController
        let operation: NavigationStackOperation

        switch direction {
        case .push:
            return
        case .back:
            guard viewControllers.count > 1 else {
                return
            }
            fromViewController = viewControllers[viewControllers.count - 1]
            toViewController = viewControllers[viewControllers.count - 2]
            operation = .back
        case .forward:
            guard let forwardViewController = forwardViewControllers.last, let topViewController else {
                return
            }
            fromViewController = topViewController
            toViewController = forwardViewController
            operation = .forward
        }

        delegate?.navigationStackController(self, willShow: toViewController, operation: operation, animated: true)

        let transition = Transition(from: fromViewController, to: toViewController, direction: direction, operation: operation)
        activeTransition = transition
        prepareTransition(transition)
    }

    func completeInteractiveTransition(committed: Bool) {
        guard let transition = activeTransition, !finishingInteractiveSwipe else {
            return
        }

        finishingInteractiveSwipe = true
        let targetProgress: CGFloat = committed ? 1 : 0

        NSAnimationContext.runAnimationGroup { context in
            context.duration = transitionDuration * 0.7
            context.timingFunction = CAMediaTimingFunction(name: committed ? .easeOut : .easeInEaseOut)
            transition.apply(progress: targetProgress, in: containerView.bounds, parallaxFactor: parallaxFactor, animated: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }

                self.finishingInteractiveSwipe = false
                self.finishTransition(transition, committed: committed, commit: {
                    self.commitStackMutation(for: transition)
                }, animated: true)
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
}
