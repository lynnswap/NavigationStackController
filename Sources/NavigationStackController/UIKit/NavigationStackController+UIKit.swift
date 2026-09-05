#if canImport(UIKit)
import UIKit
import os
internal import NavigationStackControllerRuntime

/// Receives navigation notifications and supplies orientation policy for a UIKit navigation stack.
///
/// Every method has a default implementation. Navigation requests made inside any delegate callback
/// are ignored, including orientation queries. See <doc:History> for notification timing.
@MainActor
public protocol NavigationStackControllerDelegate: AnyObject {
    /// Tells the delegate that a page is about to be displayed.
    ///
    /// - Parameters:
    ///   - controller: The navigation controller sending the notification.
    ///   - viewController: The destination page.
    ///   - operation: The attempted navigation operation.
    ///   - animated: Whether the presentation is animated.
    func navigationStackController(_ controller: NavigationStackController, willShow viewController: UIViewController, operation: NavigationStackOperation, animated: Bool)
    /// Tells the delegate which page is displayed after a transition.
    ///
    /// A cancelled interactive transition reports the original page and attempted operation.
    /// Changes that do not present a page need not send this notification; observe
    /// ``navigationStackControllerDidChangeHistory(_:)`` for committed history.
    ///
    /// - Parameters:
    ///   - controller: The navigation controller sending the notification.
    ///   - viewController: The page displayed after completion or cancellation.
    ///   - operation: The attempted navigation operation.
    ///   - animated: Whether the presentation was animated.
    func navigationStackController(_ controller: NavigationStackController, didShow viewController: UIViewController, operation: NavigationStackOperation, animated: Bool)
    /// Tells the delegate that a history change has committed.
    ///
    /// This includes navigation before the controller is displayed and explicit removal of nonempty
    /// forward history. Cancelled interactive transitions do not send this notification.
    ///
    /// - Parameter controller: The navigation controller whose history changed.
    func navigationStackControllerDidChangeHistory(_ controller: NavigationStackController)
    /// Supplies the supported interface orientations when UIKit queries the controller.
    ///
    /// After changing this policy, call the controller's inherited
    /// `setNeedsUpdateOfSupportedInterfaceOrientations()` method to request reevaluation.
    ///
    /// - Parameter controller: The navigation controller requesting the policy.
    /// - Returns: An orientation mask, or `nil` to preserve UIKit's default policy. The default is `nil`.
    func navigationStackControllerSupportedInterfaceOrientations(_ controller: NavigationStackController) -> UIInterfaceOrientationMask?
    /// Supplies the preferred orientation for presenting the navigation controller.
    ///
    /// - Parameter controller: The navigation controller requesting the policy.
    /// - Returns: The preferred orientation, or `nil` to preserve UIKit's default policy. The default is `nil`.
    func navigationStackControllerPreferredInterfaceOrientationForPresentation(_ controller: NavigationStackController) -> UIInterfaceOrientation?
}

public extension NavigationStackControllerDelegate {
    /// The default implementation leaves the notification or policy unchanged.
    func navigationStackController(_ controller: NavigationStackController, willShow viewController: UIViewController, operation: NavigationStackOperation, animated: Bool) {}
    /// The default implementation leaves the notification or policy unchanged.
    func navigationStackController(_ controller: NavigationStackController, didShow viewController: UIViewController, operation: NavigationStackOperation, animated: Bool) {}
    /// The default implementation leaves the notification or policy unchanged.
    func navigationStackControllerDidChangeHistory(_ controller: NavigationStackController) {}
    /// The default implementation leaves the notification or policy unchanged.
    func navigationStackControllerSupportedInterfaceOrientations(_ controller: NavigationStackController) -> UIInterfaceOrientationMask? { nil }
    /// The default implementation leaves the notification or policy unchanged.
    func navigationStackControllerPreferredInterfaceOrientationForPresentation(_ controller: NavigationStackController) -> UIInterfaceOrientation? { nil }
}

/// A UIKit navigation controller with retained back/forward history and interactive swipe navigation.
///
/// UIKit owns the navigation stack, containment, and navigation bar. Popped controllers remain strongly
/// retained in forward history until revisited, a new controller is pushed, the stack is replaced, or
/// ``clearForwardHistory()`` is called. Outside an active transition, forward controllers are not
/// children of this controller.
///
/// Navigation requests during a transition or delegate notification are ignored. Stack replacement
/// ignores empty arrays, duplicate instances, and controllers owned by another parent. A new push
/// ignores controllers already in either history or owned by another parent.
///
/// Use ``navigationStackDelegate`` for notifications. The native navigation delegate is reserved
/// for the built-in overlapping transitions and must not be replaced.
///
/// See <doc:UIKitIntegration> for setup and <doc:History> for history and notification timing.
///
/// > Warning: The UIKit implementation relies on undocumented APIs and runtime behavior, so extra care
/// > is needed before using it in App Store-bound projects.
@MainActor
public final class NavigationStackController: UINavigationController {
    /// The observer that receives navigation notifications and supplies orientation policy.
    ///
    /// This reference is weak. The host must retain the delegate for as long as it is needed.
    public weak var navigationStackDelegate: (any NavigationStackControllerDelegate)?

    /// The strongly retained forward history, with the next page to revisit first.
    ///
    /// Outside an active transition, these controllers are no longer children of this navigation
    /// controller. During forward navigation, the restored page may already be a child while its
    /// removal from forward history is still pending.
    /// Use ``clearForwardHistory()`` to release the library's references.
    public private(set) var forwardViewControllers: [UIViewController] = []

    /// Whether the back stack contains a page before the current top page.
    ///
    /// A true value does not guarantee that a request can start during a transition or callback.
    public var canGoBack: Bool { viewControllers.count > 1 }
    /// Whether the next forward page is available to restore.
    ///
    /// Returns false if history is empty or the first controller already has a parent, including
    /// during its restoration. Later entries are not skipped. If another container adopts the next
    /// page, detaching that page makes it available again.
    /// A true value does not guarantee that a request can start during a transition or callback.
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

    /// The baseline swipe commit distance, in points. The default is 187.5.
    ///
    /// The effective threshold is capped by ``maximumSwipeCompletionThreshold``.
    public var swipeCompletionDistance: CGFloat = 187.5
    /// The fraction of the container width that caps the swipe commit distance. The default is 0.5.
    public var maximumSwipeCompletionThreshold: CGFloat = 0.5
    /// The projection duration, in seconds, used to evaluate release velocity. The default is 0.3.
    public var swipeKineticProjectionDuration: TimeInterval = 0.3

    /// The reserved native transition delegate; use ``navigationStackDelegate`` instead.
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

    /// The delegate's supported orientations, or UIKit's policy when the delegate returns `nil`.
    ///
    /// See ``NavigationStackControllerDelegate/navigationStackControllerSupportedInterfaceOrientations(_:)``.
    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        withDelegateCallback {
            navigationStackDelegate?.navigationStackControllerSupportedInterfaceOrientations(self)
        } ?? super.supportedInterfaceOrientations
    }

    /// The delegate's preferred presentation orientation, or UIKit's policy when it returns `nil`.
    ///
    /// See ``NavigationStackControllerDelegate/navigationStackControllerPreferredInterfaceOrientationForPresentation(_:)``.
    public override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        withDelegateCallback {
            navigationStackDelegate?.navigationStackControllerPreferredInterfaceOrientationForPresentation(self)
        } ?? super.preferredInterfaceOrientationForPresentation
    }

    /// The native back stack, ordered from the root through the current top page.
    ///
    /// Assignment calls ``setViewControllers(_:animated:)`` without animation and follows its
    /// validation rules. During an interactive transition, UIKit may expose the tentative destination
    /// before the transition commits or cancels.
    public override var viewControllers: [UIViewController] {
        get { super.viewControllers }
        set { setViewControllers(newValue, animated: false) }
    }

    private static let logger = Logger(subsystem: "NavigationStackController", category: "UIKit")
    private var isConfigured = false
    private var delegateCallbackDepth = 0
    private var pendingNavigation: PendingNavigation?
    private lazy var nativeDelegate = NavigationStackNativeDelegate(controller: self)
    private lazy var gestureController = NavigationStackGestureController(navigationController: self)

    private var nextForwardViewController: UIViewController? {
        // A retained forward controller can be adopted by another container while its parent is nil.
        guard let controller = forwardViewControllers.first, controller.parent == nil else { return nil }
        return controller
    }

    private var canStartNavigation: Bool {
        delegateCallbackDepth == 0 && !isTransitioning
    }

    /// Creates a navigation controller with its first page.
    ///
    /// - Parameter rootViewController: The root page to display.
    public override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
        configure()
    }

    /// Creates an empty navigation controller with custom bar classes.
    ///
    /// - Parameters:
    ///   - navigationBarClass: A `UINavigationBar` subclass, or `nil` for the standard class.
    ///   - toolbarClass: A `UIToolbar` subclass, or `nil` for the standard class.
    public override init(navigationBarClass: AnyClass?, toolbarClass: AnyClass?) {
        super.init(navigationBarClass: navigationBarClass, toolbarClass: toolbarClass)
        configure()
    }

    /// Creates a navigation controller using UIKit's nib initialization.
    ///
    /// - Parameters:
    ///   - nibNameOrNil: The nib name, or `nil`.
    ///   - nibBundleOrNil: The bundle containing the nib, or `nil` for UIKit's default lookup.
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        configure()
    }

    /// Restores a navigation controller from an archive and installs its navigation behavior.
    ///
    /// - Parameter coder: The decoder containing the archived controller.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isConfigured = true
        super.delegate = nativeDelegate
    }

    /// Installs bidirectional navigation gestures after UIKit loads the view.
    public override func viewDidLoad() {
        super.viewDidLoad()
        gestureController.install()
        gestureController.setEnabled(allowsBackForwardNavigationGestures)
    }

    /// Restores the controller's gesture ownership after the view appears.
    ///
    /// - Parameter animated: Whether the appearance was animated.
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        gestureController.install()
    }

    /// Pushes a new page and clears forward history after navigation succeeds.
    ///
    /// Requests during transitions or delegate callbacks are ignored, as are controllers already
    /// in either history, this navigation controller itself, or controllers with an existing parent.
    ///
    /// - Parameters:
    ///   - viewController: The unparented page to append.
    ///   - animated: Whether to animate the presentation.
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

    /// Replaces the back stack and clears forward history after navigation succeeds.
    ///
    /// Ignores empty arrays, duplicate instances, this navigation controller itself, and pages owned
    /// by another parent. Requests during transitions or delegate callbacks are also ignored.
    /// Replacing an identical stack is a no-op unless there is forward history to clear.
    ///
    /// - Parameters:
    ///   - viewControllers: The root-to-top stack to display.
    ///   - animated: Whether to animate the change of top page.
    public override func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
        guard isConfigured else {
            super.setViewControllers(viewControllers, animated: animated)
            return
        }
        guard canStartNavigation, let destination = viewControllers.last, isValidStack(viewControllers) else { return }
        guard !Self.sameInstances(self.viewControllers, viewControllers) || !forwardViewControllers.isEmpty else { return }

        navigate(to: destination, stack: viewControllers, operation: .set, forwardHistory: [], animated: animated)
    }

    /// Removes the current top page into forward history.
    ///
    /// - Parameter animated: Whether to animate the presentation.
    /// - Returns: The outgoing page accepted for removal, or `nil` if there is no previous page or
    ///   a transition or delegate callback prevents the request. This does not signal animation completion.
    @discardableResult
    public override func popViewController(animated: Bool) -> UIViewController? {
        guard isConfigured else { return super.popViewController(animated: animated) }
        guard canStartNavigation, viewControllers.count > 1 else { return nil }
        let outgoing = viewControllers[viewControllers.count - 1]
        navigate(to: viewControllers[viewControllers.count - 2], stack: Array(viewControllers.dropLast()), operation: .back,
                 forwardHistory: [outgoing] + forwardViewControllers, animated: animated)
        return outgoing
    }

    /// Moves every page after the specified page into forward history, in stack order.
    ///
    /// - Parameters:
    ///   - viewController: The page to return to in the current back stack.
    ///   - animated: Whether to animate the presentation.
    /// - Returns: The pages accepted for removal in their original stack order, or `nil` if the target
    ///   is absent, already on top, or a transition or delegate callback prevents the request.
    ///   This does not signal animation completion.
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

    /// Moves every page above the root into forward history, in stack order.
    ///
    /// - Parameter animated: Whether to animate the presentation.
    /// - Returns: The pages accepted for removal, or `nil` if there is no previous page or a transition
    ///   or delegate callback prevents the request. This does not signal animation completion.
    @discardableResult
    public override func popToRootViewController(animated: Bool) -> [UIViewController]? {
        guard isConfigured else { return super.popToRootViewController(animated: animated) }
        guard let root = viewControllers.first else { return nil }
        return popToViewController(root, animated: animated)
    }

    /// Moves backward in history by calling ``popViewController(animated:)``.
    ///
    /// - Parameter animated: Whether to animate the presentation.
    /// - Returns: The outgoing page accepted for removal, or `nil` if no request can start.
    ///   This does not signal animation completion.
    @discardableResult
    public func goBack(animated: Bool) -> UIViewController? {
        popViewController(animated: animated)
    }

    /// Restores the next forward controller, preserving the rest of forward history.
    ///
    /// The next page must have no parent. If another container adopted it, this method ignores the
    /// request without skipping to a later page.
    ///
    /// - Parameter animated: Whether to animate the presentation.
    /// - Returns: The page accepted for restoration, or `nil` if no forward page is available or
    ///   a transition or delegate callback prevents the request. This does not signal animation completion.
    ///
    /// See <doc:History> for the distinction between display and history notifications.
    @discardableResult
    public func goForward(animated: Bool) -> UIViewController? {
        guard canStartNavigation, let destination = nextForwardViewController else { return nil }
        navigate(to: destination, stack: viewControllers + [destination], operation: .forward,
                 forwardHistory: Array(forwardViewControllers.dropFirst()), animated: animated)
        return destination
    }

    /// Releases this controller's forward-history references.
    ///
    /// Requests during transitions or delegate callbacks are ignored. Clearing nonempty history sends
    /// a history-change notification; clearing an already empty history does nothing.
    public func clearForwardHistory() {
        guard canStartNavigation, !forwardViewControllers.isEmpty else { return }
        forwardViewControllers.removeAll()
        withDelegateCallback { navigationStackDelegate?.navigationStackControllerDidChangeHistory(self) }
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
            withDelegateCallback { navigationStackDelegate?.navigationStackControllerDidChangeHistory(self) }
        }
        if isViewLoaded {
            gestureController.install()
        }
        if let shownViewController {
            withDelegateCallback {
                navigationStackDelegate?.navigationStackController(self, didShow: shownViewController,
                                                                  operation: transaction.operation, animated: animated)
            }
        }
    }

    private func withDelegateCallback<Result>(_ body: () -> Result) -> Result {
        delegateCallbackDepth += 1
        defer { delegateCallbackDepth -= 1 }
        return body()
    }

    fileprivate func willShow(_ viewController: UIViewController, animated: Bool) {
        guard let transaction = pendingNavigation, viewController === transaction.destination else { return }
        withDelegateCallback {
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
        makeNavigationAnimator(operation: operation, layoutDirection: navigationController.view.effectiveUserInterfaceLayoutDirection)
    }

    func navigationController(_ navigationController: UINavigationController,
                              interactionControllerFor animationController: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)? {
        controller?.interactionController
    }
}
#endif
