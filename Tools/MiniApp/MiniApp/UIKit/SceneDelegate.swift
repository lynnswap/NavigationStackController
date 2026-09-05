#if canImport(UIKit)
import NavigationStackController
import UIKit

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate, NavigationStackControllerDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // AppDelegate registers this delegate with UIWindowScene as the scene class.
        let windowScene = scene as! UIWindowScene
        let navigation = NavigationStackController(rootViewController: DemoPageController(number: 1))
        navigation.navigationStackDelegate = self

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = navigation
        self.window = window
        window.makeKeyAndVisible()
    }

    func navigationStackControllerDidChangeHistory(_ controller: NavigationStackController) {
        (controller.topViewController as? DemoPageController)?.updateNavigationButtons()
    }

    func navigationStackController(
        _ controller: NavigationStackController,
        didShow viewController: UIViewController,
        operation: NavigationStackOperation,
        animated: Bool
    ) {
        (viewController as? DemoPageController)?.updateNavigationButtons()
    }
}
#endif
