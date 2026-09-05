import NavigationStackController
import Testing
import UIKit
import UIKitConsumer

@Suite
struct UIKitConsumerTests {
    @Test
    func actualProductSupportsNativeNavigationAndForwardHistory() throws {
        let navigation = UIKitConsumer.makeNavigationController()
        let root = try #require(navigation.topViewController)
        let document = UIViewController()
        document.title = "Document"
        let observer = ConsumerNavigationObserver()
        navigation.navigationStackDelegate = observer

        let nativeController: UINavigationController = navigation
        #expect(nativeController.supportedInterfaceOrientations == .portrait)
        #expect(nativeController.preferredInterfaceOrientationForPresentation == .portrait)
        nativeController.pushViewController(document, animated: false)
        #expect(document.navigationController === nativeController)
        #expect(nativeController.topViewController === document)
        #expect(navigation.canGoBack)
        #expect(!navigation.isTransitioning)

        #expect(navigation.goBack(animated: false) === document)
        #expect(navigation.canGoForward)
        #expect(navigation.forwardViewControllers.first === document)
        #expect(navigation.goForward(animated: false) === document)
        #expect(navigation.forwardViewControllers.isEmpty)

        _ = nativeController.popToRootViewController(animated: false)
        navigation.clearForwardHistory()
        #expect(navigation.topViewController === root)
        #expect(!navigation.canGoBack)
        #expect(!navigation.canGoForward)
        #expect(observer.historyChangeCount == 5)
        #expect(navigation.navigationStackDelegate === observer)
    }
}

private final class ConsumerNavigationObserver: NavigationStackControllerDelegate {
    var historyChangeCount = 0

    func navigationStackControllerSupportedInterfaceOrientations(_ controller: NavigationStackController) -> UIInterfaceOrientationMask? {
        .portrait
    }

    func navigationStackControllerPreferredInterfaceOrientationForPresentation(_ controller: NavigationStackController) -> UIInterfaceOrientation? {
        .portrait
    }

    func navigationStackController(
        _ controller: NavigationStackController,
        willShow viewController: UIViewController,
        operation: NavigationStackOperation,
        animated: Bool
    ) {}

    func navigationStackController(
        _ controller: NavigationStackController,
        didShow viewController: UIViewController,
        operation: NavigationStackOperation,
        animated: Bool
    ) {}

    func navigationStackControllerDidChangeHistory(_ controller: NavigationStackController) {
        historyChangeCount += 1
    }
}
