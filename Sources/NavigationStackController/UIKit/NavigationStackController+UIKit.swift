#if canImport(UIKit)
import UIKit
import os

/// Receives display and committed-history notifications from a navigation stack.
@MainActor
public protocol NavigationStackControllerDelegate: AnyObject {
    func navigationStackController(_ controller: NavigationStackController, willShow viewController: UIViewController, operation: NavigationStackOperation, animated: Bool)
    /// A cancelled interactive transition reports its original view controller and attempted operation.
    func navigationStackController(_ controller: NavigationStackController, didShow viewController: UIViewController, operation: NavigationStackOperation, animated: Bool)
    /// Called after a successful navigation or explicit forward-history removal.
    func navigationStackControllerDidChangeHistory(_ controller: NavigationStackController)
}

public extension NavigationStackControllerDelegate {
    func navigationStackController(_ controller: NavigationStackController, willShow viewController: UIViewController, operation: NavigationStackOperation, animated: Bool) {}
    func navigationStackController(_ controller: NavigationStackController, didShow viewController: UIViewController, operation: NavigationStackOperation, animated: Bool) {}
    func navigationStackControllerDidChangeHistory(_ controller: NavigationStackController) {}
}

/// A UIKit navigation controller with retained back/forward history and interactive swipe navigation.
///
/// UIKit owns the navigation stack, containment, and navigation bar. Popped controllers remain strongly
/// retained in forward history until revisited, a new controller is pushed, the stack is replaced, or
/// ``clearForwardHistory()`` is called. Forward controllers are not children of this controller.
///
/// Navigation requests during a transition or delegate notification are ignored. Stack replacement
/// ignores empty arrays, duplicate instances, and controllers owned by another parent. A new push
/// ignores controllers already in either history or owned by another parent.
///
/// Use ``navigationStackDelegate`` for notifications. The native navigation delegate is reserved
/// for the built-in overlapping transitions and must not be replaced.
@MainActor
public final class NavigationStackController: UINavigationController {
    public weak var navigationStackDelegate: (any NavigationStackControllerDelegate)?

    /// The next controller to revisit is the first element.
    public private(set) var forwardViewControllers: [UIViewController] = []

    public var canGoBack: Bool { viewControllers.count > 1 }
    /// Whether the next forward controller is available for containment here.
    public var canGoForward: Bool { nextForwardViewController != nil }

    /// Whether a navigation or another UIKit transition currently prevents a new request.
    public var isTransitioning: Bool { pendingNavigation != nil || transitionCoordinator != nil }

    /// Enables the controller's bidirectional horizontal pan gesture. Defaults to true.
    public var allowsBackForwardNavigationGestures = true {
        didSet {
            if isViewLoaded {
                gestureController.setEnabled(allowsBackForwardNavigationGestures)
            }
        }
    }

    /// The duration of noninteractive navigation animations, in seconds.
    public var transitionDuration: TimeInterval = 0.25
    /// The fraction of the width traversed by the background page during an overlapping transition.
    public var parallaxFactor: CGFloat = 0.28
    /// The baseline swipe commit distance, in points.
    public var swipeCompletionDistance: CGFloat = 187.5
    /// The fraction of the width that caps the swipe commit distance.
    public var maximumSwipeCompletionThreshold: CGFloat = 0.5
    /// The time interval used to project release velocity when deciding whether to finish a swipe.
    public var swipeKineticProjectionDuration: TimeInterval = 0.3

    @available(*, unavailable, message: "NavigationStackController owns its transition delegate. Use navigationStackDelegate.")
    public override var delegate: (any UINavigationControllerDelegate)? {
        get { super.delegate }
        set {
            if !isConfigured {
                super.delegate = newValue
            } else if newValue !== nativeDelegate {
                Self.logger.error("NavigationStackController rejected replacement of its transition delegate. Use navigationStackDelegate.")
            }
        }
    }

    /// Assigning this property is equivalent to replacing the stack without animation.
    public override var viewControllers: [UIViewController] {
        get { super.viewControllers }
        set { setViewControllers(newValue, animated: false) }
    }

    private static let logger = Logger(subsystem: "NavigationStackController", category: "UIKit")
    private var isConfigured = false
    private var notificationDepth = 0
    private var pendingNavigation: PendingNavigation?
    private lazy var nativeDelegate = NavigationStackNativeDelegate(controller: self)
    private lazy var gestureController = NavigationStackGestureController(navigationController: self)

    private var nextForwardViewController: UIViewController? {
        // A retained forward controller can be adopted by another container while its parent is nil.
        guard let controller = forwardViewControllers.first, controller.parent == nil else { return nil }
        return controller
    }

    private var canStartNavigation: Bool {
        notificationDepth == 0 && !isTransitioning
    }

    public override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
        configure()
    }

    public override init(navigationBarClass: AnyClass?, toolbarClass: AnyClass?) {
        super.init(navigationBarClass: navigationBarClass, toolbarClass: toolbarClass)
        configure()
    }

    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        configure()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isConfigured = true
        super.delegate = nativeDelegate
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        gestureController.install()
        gestureController.setEnabled(allowsBackForwardNavigationGestures)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        gestureController.install()
    }

    /// Pushes a new controller and clears forward history after the navigation succeeds.
    public override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        guard isConfigured else {
            super.pushViewController(viewController, animated: animated)
            return
        }
        guard canStartNavigation,
              viewController !== self,
              viewController.parent == nil,
              !viewControllers.contains(where: { $0 === viewController }),
              !forwardViewControllers.contains(where: { $0 === viewController }) else { return }

        navigate(to: viewController, stack: viewControllers + [viewController], operation: .push, forwardHistory: [], animated: animated)
    }

    /// Replaces the back stack and clears forward history after the navigation succeeds.
    public override func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
        guard isConfigured else {
            super.setViewControllers(viewControllers, animated: animated)
            return
        }
        guard canStartNavigation, let destination = viewControllers.last, isValidStack(viewControllers) else { return }
        guard !Self.sameInstances(self.viewControllers, viewControllers) || !forwardViewControllers.isEmpty else { return }

        navigate(to: destination, stack: viewControllers, operation: .set, forwardHistory: [], animated: animated)
    }

    /// Removes the current top controller into forward history.
    @discardableResult
    public override func popViewController(animated: Bool) -> UIViewController? {
        guard isConfigured else { return super.popViewController(animated: animated) }
        guard canStartNavigation, viewControllers.count > 1 else { return nil }
        let outgoing = viewControllers[viewControllers.count - 1]
        navigate(to: viewControllers[viewControllers.count - 2], stack: Array(viewControllers.dropLast()), operation: .back,
                 forwardHistory: [outgoing] + forwardViewControllers, animated: animated)
        return outgoing
    }

    /// Moves every controller after the specified controller into forward history, in stack order.
    @discardableResult
    public override func popToViewController(_ viewController: UIViewController, animated: Bool) -> [UIViewController]? {
        guard isConfigured else { return super.popToViewController(viewController, animated: animated) }
        guard canStartNavigation,
              let index = viewControllers.firstIndex(where: { $0 === viewController }),
              index < viewControllers.count - 1 else { return nil }
        let removed = Array(viewControllers.dropFirst(index + 1))
        navigate(to: viewController, stack: Array(viewControllers.prefix(index + 1)), operation: .back,
                 forwardHistory: removed + forwardViewControllers, animated: animated)
        return removed
    }

    @discardableResult
    public override func popToRootViewController(animated: Bool) -> [UIViewController]? {
        guard isConfigured else { return super.popToRootViewController(animated: animated) }
        guard let root = viewControllers.first else { return nil }
        return popToViewController(root, animated: animated)
    }

    /// An alias for ``popViewController(animated:)``; returns the outgoing controller, or nil.
    @discardableResult
    public func goBack(animated: Bool) -> UIViewController? {
        popViewController(animated: animated)
    }

    /// Restores the next forward controller, preserving the rest of forward history.
    ///
    /// Returns the restored controller, or nil if no request can start. The return value describes
    /// admission, not animation completion. Observe ``navigationStackDelegate`` for completion.
    @discardableResult
    public func goForward(animated: Bool) -> UIViewController? {
        guard canStartNavigation, let destination = nextForwardViewController else { return nil }
        navigate(to: destination, stack: viewControllers + [destination], operation: .forward,
                 forwardHistory: Array(forwardViewControllers.dropFirst()), animated: animated)
        return destination
    }

    /// Releases this controller's forward-history references. Requests during navigation or notifications are ignored.
    public func clearForwardHistory() {
        guard canStartNavigation, !forwardViewControllers.isEmpty else { return }
        forwardViewControllers.removeAll()
        notify { navigationStackDelegate?.navigationStackControllerDidChangeHistory(self) }
    }

    func beginInteractiveNavigation(_ operation: NavigationStackOperation) -> UIPercentDrivenInteractiveTransition? {
        guard canStartNavigation, isViewLoaded, view.window != nil else { return nil }
        let interaction = UIPercentDrivenInteractiveTransition()
        interaction.completionCurve = .easeOut
        switch operation {
        case .back:
            guard viewControllers.count > 1 else { return nil }
            let outgoing = viewControllers[viewControllers.count - 1]
            navigate(to: viewControllers[viewControllers.count - 2], stack: Array(viewControllers.dropLast()), operation: .back,
                     forwardHistory: [outgoing] + forwardViewControllers, animated: true, interaction: interaction)
        case .forward:
            guard let destination = nextForwardViewController else { return nil }
            navigate(to: destination, stack: viewControllers + [destination], operation: .forward,
                     forwardHistory: Array(forwardViewControllers.dropFirst()), animated: true, interaction: interaction)
        case .push, .set:
            return nil
        }
        return pendingNavigation?.interaction
    }

    private func isValidStack(_ controllers: [UIViewController]) -> Bool {
        guard !controllers.isEmpty else { return false }
        var identities = Set<ObjectIdentifier>()
        return controllers.allSatisfy {
            $0 !== self && ($0.parent == nil || $0.parent === self)
                && identities.insert(ObjectIdentifier($0)).inserted
        }
    }

    private static func sameInstances(_ lhs: [UIViewController], _ rhs: [UIViewController]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0 === $1 }
    }

    private func navigate(to destination: UIViewController, stack controllers: [UIViewController], operation: NavigationStackOperation,
                          forwardHistory: [UIViewController], animated: Bool,
                          interaction: UIPercentDrivenInteractiveTransition? = nil) {
        let waitsForDisplay = isViewLoaded && view.window != nil && topViewController !== destination
        let transaction = PendingNavigation(operation: operation, destination: destination,
                                            forwardHistory: forwardHistory, interaction: interaction)
        pendingNavigation = transaction
        // setViewControllers is the sole native mutation boundary: UIKit selects push/pop from the endpoints.
        // Calling several native mutators would let their internal calls reenter our public overrides.
        super.setViewControllers(controllers, animated: animated)
        guard pendingNavigation === transaction else { return }
        if let coordinator = transitionCoordinator {
            transaction.usesTransitionCoordinator = true
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard let self else { return }
                self.complete(transaction, succeeded: !context.isCancelled,
                              shownViewController: self.topViewController, animated: context.isAnimated)
            }
        } else if !waitsForDisplay {
            complete(transaction, succeeded: true, shownViewController: nil, animated: false)
        }
        // UIKit also delivers nonanimated display callbacks during a later layout pass.
    }

    private func complete(_ transaction: PendingNavigation, succeeded: Bool,
                          shownViewController: UIViewController?, animated: Bool) {
        guard pendingNavigation === transaction else { return }
        pendingNavigation = nil
        if succeeded {
            forwardViewControllers = transaction.forwardHistory
            notify { navigationStackDelegate?.navigationStackControllerDidChangeHistory(self) }
        }
        if isViewLoaded {
            gestureController.install()
        }
        if let shownViewController {
            notify {
                navigationStackDelegate?.navigationStackController(self, didShow: shownViewController,
                                                                  operation: transaction.operation, animated: animated)
            }
        }
    }

    private func notify(_ body: () -> Void) {
        notificationDepth += 1
        defer { notificationDepth -= 1 }
        body()
    }

    fileprivate func willShow(_ viewController: UIViewController, animated: Bool) {
        guard let transaction = pendingNavigation, viewController === transaction.destination else { return }
        notify {
            navigationStackDelegate?.navigationStackController(self, willShow: viewController,
                                                              operation: transaction.operation, animated: animated)
        }
    }

    fileprivate func didShow(_ viewController: UIViewController, animated: Bool) {
        // Cancelled native transitions may omit didShow. Their coordinator owns terminal notification.
        guard let transaction = pendingNavigation, !transaction.usesTransitionCoordinator,
              viewController === transaction.destination else { return }
        complete(transaction, succeeded: true, shownViewController: viewController, animated: animated)
    }

    fileprivate var interactionController: UIPercentDrivenInteractiveTransition? {
        pendingNavigation?.interaction
    }

    private final class PendingNavigation {
        var usesTransitionCoordinator = false
        let operation: NavigationStackOperation
        let destination: UIViewController
        let forwardHistory: [UIViewController]
        let interaction: UIPercentDrivenInteractiveTransition?

        init(operation: NavigationStackOperation, destination: UIViewController,
             forwardHistory: [UIViewController], interaction: UIPercentDrivenInteractiveTransition?) {
            self.operation = operation
            self.destination = destination
            self.forwardHistory = forwardHistory
            self.interaction = interaction
        }
    }
}

@MainActor
private final class NavigationStackNativeDelegate: NSObject, UINavigationControllerDelegate {
    private weak var controller: NavigationStackController?

    init(controller: NavigationStackController) {
        self.controller = controller
    }

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        controller?.willShow(viewController, animated: animated)
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        controller?.didShow(viewController, animated: animated)
    }

    func navigationController(_ navigationController: UINavigationController,
                              animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController, to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        guard let controller else { return nil }
        return NavigationStackAnimator(operation: operation, duration: controller.transitionDuration,
                                       parallaxFactor: controller.parallaxFactor)
    }

    func navigationController(_ navigationController: UINavigationController,
                              interactionControllerFor animationController: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)? {
        controller?.interactionController
    }
}
#endif
