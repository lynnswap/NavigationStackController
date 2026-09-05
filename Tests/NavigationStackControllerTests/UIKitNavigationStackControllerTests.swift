#if canImport(UIKit)
import Testing
import UIKit
@testable import NavigationStackController

@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct UIKitNavigationStackControllerTests {
    @Test
    func rootAndRoundTripPreserveNativeControllerIdentity() {
        let root = UIKitTestViewController()
        let first = UIKitTestViewController()
        let second = UIKitTestViewController()
        let navigation = NavigationStackController(rootViewController: root)

        #expect(navigation.topViewController === root)
        #expect(!navigation.canGoBack)
        #expect(!navigation.canGoForward)

        navigation.pushViewController(first, animated: false)
        navigation.pushViewController(second, animated: false)
        #expect(navigation.goBack(animated: false) === second)
        #expect(navigation.goBack(animated: false) === first)
        #expect(ids(navigation.viewControllers) == ids([root]))
        #expect(ids(navigation.forwardViewControllers) == ids([first, second]))
        #expect(navigation.canGoForward)
        #expect(first.parent == nil)
        #expect(second.parent == nil)

        #expect(navigation.goForward(animated: false) === first)
        #expect(navigation.goForward(animated: false) === second)
        #expect(ids(navigation.viewControllers) == ids([root, first, second]))
        #expect(first.navigationController === navigation)
        #expect(second.navigationController === navigation)
        #expect(navigation.forwardViewControllers.isEmpty)
        #expect(navigation.goForward(animated: false) == nil)
    }

    @Test
    func nativePopToAndPopToRootKeepNextVisitFirst() {
        let pages = (0..<4).map { _ in UIKitTestViewController() }
        let navigation = NavigationStackController(rootViewController: pages[0])
        navigation.setViewControllers(pages, animated: false)

        let popped = navigation.popToViewController(pages[1], animated: false)
        #expect(ids(popped ?? []) == ids([pages[2], pages[3]]))
        #expect(ids(navigation.forwardViewControllers) == ids([pages[2], pages[3]]))

        let poppedToRoot = navigation.popToRootViewController(animated: false)
        #expect(ids(poppedToRoot ?? []) == ids([pages[1]]))
        #expect(ids(navigation.forwardViewControllers) == ids(Array(pages.dropFirst())))
        #expect(navigation.goBack(animated: false) == nil)

        for page in pages.dropFirst() {
            #expect(navigation.goForward(animated: false) === page)
        }
        #expect(ids(navigation.viewControllers) == ids(pages))
    }

    @Test
    func newPushClearsForwardButForwardNavigationPreservesRemainingVisits() {
        let root = UIKitTestViewController()
        let first = UIKitTestViewController()
        let second = UIKitTestViewController()
        let replacement = UIKitTestViewController()
        let navigation = NavigationStackController(rootViewController: root)
        navigation.setViewControllers([root, first, second], animated: false)
        _ = navigation.popToRootViewController(animated: false)

        #expect(navigation.goForward(animated: false) === first)
        #expect(ids(navigation.forwardViewControllers) == ids([second]))
        navigation.pushViewController(replacement, animated: false)
        #expect(ids(navigation.viewControllers) == ids([root, first, replacement]))
        #expect(navigation.forwardViewControllers.isEmpty)
        #expect(second.parent == nil)
    }

    @Test
    func sameTopSetAndInheritedPropertyAssignmentReplaceStackAndClearForward() {
        let root = UIKitTestViewController()
        let first = UIKitTestViewController()
        let second = UIKitTestViewController()
        let replacementRoot = UIKitTestViewController()
        let navigation = NavigationStackController(rootViewController: root)
        let observer = UIKitHistoryObserver()
        navigation.navigationStackDelegate = observer
        navigation.setViewControllers([root, first, second], animated: false)
        _ = navigation.popViewController(animated: false)
        observer.historyChangeCount = 0

        navigation.setViewControllers([replacementRoot, first], animated: false)
        #expect(ids(navigation.viewControllers) == ids([replacementRoot, first]))
        #expect(navigation.forwardViewControllers.isEmpty)
        #expect(observer.historyChangeCount == 1)

        navigation.pushViewController(second, animated: false)
        _ = navigation.popViewController(animated: false)
        observer.historyChangeCount = 0
        navigation.viewControllers = [root, first]
        #expect(ids(navigation.viewControllers) == ids([root, first]))
        #expect(navigation.forwardViewControllers.isEmpty)
        #expect(observer.historyChangeCount == 1)
        #expect(!navigation.isTransitioning)
    }

    @Test
    func invalidInputsLeaveStackAndForwardHistoryUnchanged() {
        let root = UIKitTestViewController()
        let first = UIKitTestViewController()
        let second = UIKitTestViewController()
        let parent = UIViewController()
        let parented = UIKitTestViewController()
        parent.addChild(parented)
        parented.didMove(toParent: parent)
        let navigation = NavigationStackController(rootViewController: root)
        navigation.setViewControllers([root, first, second], animated: false)
        _ = navigation.popViewController(animated: false)
        let observer = UIKitHistoryObserver()
        navigation.navigationStackDelegate = observer

        navigation.pushViewController(first, animated: false)
        navigation.pushViewController(second, animated: false)
        navigation.pushViewController(parented, animated: false)
        navigation.setViewControllers([root, first, first], animated: false)
        navigation.setViewControllers([root, parented], animated: false)
        navigation.viewControllers = []
        #expect(navigation.popToViewController(parented, animated: false) == nil)

        #expect(ids(navigation.viewControllers) == ids([root, first]))
        #expect(ids(navigation.forwardViewControllers) == ids([second]))
        #expect(parented.parent === parent)
        #expect(observer.historyChangeCount == 0)
        #expect(!navigation.isTransitioning)
    }

    @Test
    func clearingForwardHistoryReleasesItsControllers() {
        let navigation = NavigationStackController(rootViewController: UIKitTestViewController())
        weak var releasedPage: UIViewController?
        autoreleasepool {
            let page = UIKitTestViewController()
            releasedPage = page
            navigation.pushViewController(page, animated: false)
            _ = navigation.popViewController(animated: false)
        }

        #expect(releasedPage != nil)
        autoreleasepool {
            navigation.clearForwardHistory()
        }
        #expect(navigation.forwardViewControllers.isEmpty)
        #expect(releasedPage == nil)
    }

    @Test
    func historyDelegateReceivesCallbacksWithReentrantCommandsIgnored() async {
        let root = UIKitTestViewController()
        let first = UIKitTestViewController()
        let rejected = UIKitTestViewController()
        let navigation = NavigationStackController(rootViewController: root)
        let window = await show(navigation, visible: root)
        defer { close(window) }
        let history = UIKitHistoryObserver()
        navigation.navigationStackDelegate = history

        let attemptReentrantMutation: () -> Void = {
            navigation.pushViewController(rejected, animated: false)
            _ = navigation.popViewController(animated: false)
            navigation.setViewControllers([rejected], animated: false)
            navigation.clearForwardHistory()
        }
        history.onWillShow = attemptReentrantMutation
        history.onHistoryChange = attemptReentrantMutation

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            history.onDidShow = {
                attemptReentrantMutation()
                history.onDidShow = nil
                continuation.resume()
            }
            navigation.pushViewController(first, animated: false)
            navigation.view.layoutIfNeeded()
        }

        #expect(ids(navigation.viewControllers) == ids([root, first]))
        #expect(rejected.parent == nil)
        #expect(history.willShowOperations == [.push])
        #expect(history.didShowOperations == [.push])
        #expect(history.historyChangeCount == 1)
        #expect(!navigation.isTransitioning)
    }

    @Test
    func nativeDelegateOwnerSurvivesReplacementThroughBaseClass() throws {
        let root = UIKitTestViewController()
        let first = UIKitTestViewController()
        let navigation = NavigationStackController(rootViewController: root)
        let native: UINavigationController = navigation
        let owner = try #require(native.delegate)
        let replacement = UIKitNativeObserver()

        native.delegate = replacement
        #expect(native.delegate === owner)
        native.delegate = nil
        #expect(native.delegate === owner)

        native.pushViewController(first, animated: false)
        #expect(native.popViewController(animated: false) === first)
        #expect(navigation.forwardViewControllers.first === first)
        #expect(navigation.goForward(animated: false) === first)
    }

    @Test(arguments: [NavigationStackOperation.back, .forward], [false, true])
    func interactiveNavigationCommitsOnlyOnCompletion(
        operation: NavigationStackOperation,
        completes: Bool
    ) async throws {
        let root = UIKitTestViewController()
        let first = UIKitTestViewController()
        let second = UIKitTestViewController()
        let rejected = UIKitTestViewController()
        let navigation = NavigationStackController(rootViewController: root)
        navigation.transitionDuration = 0.05
        navigation.setViewControllers([root, first, second], animated: false)
        if operation == .forward {
            _ = navigation.popViewController(animated: false)
        }
        let initiallyVisible = operation == .back ? second : first
        let window = await show(navigation, visible: initiallyVisible)
        defer { close(window) }
        let history = UIKitHistoryObserver()
        navigation.navigationStackDelegate = history
        let priorForward = ids(navigation.forwardViewControllers)

        let driver = try #require(navigation.beginInteractiveNavigation(operation))
        navigation.view.layoutIfNeeded()
        #expect(navigation.isTransitioning)
        #expect(ids(navigation.forwardViewControllers) == priorForward)

        let admittedStack = ids(navigation.viewControllers)
        navigation.pushViewController(rejected, animated: false)
        #expect(navigation.goBack(animated: false) == nil)
        #expect(navigation.goForward(animated: false) == nil)
        navigation.setViewControllers([rejected], animated: false)
        navigation.clearForwardHistory()
        #expect(ids(navigation.viewControllers) == admittedStack)
        #expect(ids(navigation.forwardViewControllers) == priorForward)
        #expect(rejected.parent == nil)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            history.onDidShow = {
                history.onDidShow = nil
                continuation.resume()
            }
            driver.update(0.6)
            if completes {
                driver.finish()
            } else {
                driver.cancel()
            }
        }

        let endsAtSecond = operation == .back ? !completes : completes
        #expect(ids(navigation.viewControllers) == ids(endsAtSecond ? [root, first, second] : [root, first]))
        #expect(ids(navigation.forwardViewControllers) == ids(endsAtSecond ? [] : [second]))
        #expect(navigation.topViewController === (endsAtSecond ? second : first))
        #expect(navigation.visibleViewController === navigation.topViewController)
        #expect(!navigation.isTransitioning)
        #expect(history.historyChangeCount == (completes ? 1 : 0))
        #expect(first.view.transform == .identity)
        #expect(second.view.transform == .identity)
        #expect(first.view.alpha == 1)
        #expect(second.view.alpha == 1)
    }

    private func show(
        _ navigation: NavigationStackController,
        visible: UIKitTestViewController
    ) async -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            visible.onDidAppear = { continuation.resume() }
            window.rootViewController = navigation
            window.makeKeyAndVisible()
            navigation.view.layoutIfNeeded()
            window.layoutIfNeeded()
        }
        return window
    }

    private func close(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
    }

    private func ids(_ controllers: [UIViewController]) -> [ObjectIdentifier] {
        controllers.map(ObjectIdentifier.init)
    }
}

@MainActor
private final class UIKitTestViewController: UIViewController {
    var onDidAppear: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let completion = onDidAppear
        onDidAppear = nil
        completion?()
    }
}

@MainActor
private final class UIKitNativeObserver: NSObject, UINavigationControllerDelegate {}

@MainActor
private final class UIKitHistoryObserver: NavigationStackControllerDelegate {
    var willShowOperations: [NavigationStackOperation] = []
    var didShowOperations: [NavigationStackOperation] = []
    var historyChangeCount = 0
    var onWillShow: (() -> Void)?
    var onDidShow: (() -> Void)?
    var onHistoryChange: (() -> Void)?

    func navigationStackController(
        _ controller: NavigationStackController,
        willShow viewController: UIViewController,
        operation: NavigationStackOperation,
        animated: Bool
    ) {
        willShowOperations.append(operation)
        onWillShow?()
    }

    func navigationStackController(
        _ controller: NavigationStackController,
        didShow viewController: UIViewController,
        operation: NavigationStackOperation,
        animated: Bool
    ) {
        didShowOperations.append(operation)
        onDidShow?()
    }

    func navigationStackControllerDidChangeHistory(_ controller: NavigationStackController) {
        historyChangeCount += 1
        onHistoryChange?()
    }
}
#endif
