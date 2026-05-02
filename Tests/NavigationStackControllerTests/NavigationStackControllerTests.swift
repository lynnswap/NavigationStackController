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
@Test func loadingViewInstallsTopViewController() {
    let rootViewController = TestViewController()
    let pushedViewController = TestViewController()
    let navigationController = NavigationStackController(rootViewController: rootViewController)

    navigationController.pushViewController(pushedViewController, animated: false)
    _ = navigationController.view

    #expect(pushedViewController.view.superview === navigationController.view)
    #expect(rootViewController.view.superview == nil)
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

private final class TestViewController: NSViewController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    }
}
