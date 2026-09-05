# Integrating with UIKit

Present a navigation controller and observe its history from a native UIKit application.

## Create the navigation controller

Import the library in your scene delegate and install ``NavigationStackController`` as the window's root controller. This example uses plain pages so it can run without additional application types.

```swift
import UIKit
import NavigationStackController

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let root = UIViewController()
        root.title = "Home"
        root.view.backgroundColor = .systemBackground

        let navigation = NavigationStackController(rootViewController: root)
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = navigation
        self.window = window
        window.makeKeyAndVisible()
    }
}
```

Select this scene delegate in your application's scene configuration. You can also place the controller in a tab or split view controller, or contain it in your own controller.

UIKit manages child containment, each page's `navigationItem`, the navigation bar, and the toolbar. Use inherited APIs such as `setNavigationBarHidden(_:animated:)` to control the standard interface. The package owns the navigation delegate and navigation gestures.

## Observe navigation

Assign a retained observer to `navigationStackDelegate`; the reference is weak. All methods in ``NavigationStackControllerDelegate`` have default implementations.

```swift
@MainActor
final class NavigationObserver: NavigationStackControllerDelegate {
    func navigationStackControllerDidChangeHistory(
        _ controller: NavigationStackController
    ) {
        // Update Back and Forward controls from canGoBack and canGoForward.
    }

    func navigationStackController(
        _ controller: NavigationStackController,
        didShow viewController: UIViewController,
        operation: NavigationStackOperation,
        animated: Bool
    ) {
        // Update UI for the displayed page, including a cancelled swipe.
    }
}
```

Keep the observer in a property of your host and assign it to the navigation controller. Display callbacks describe presentation; the history callback describes committed changes. See <doc:History> for their timing and cancellation behavior.

To supply orientation policy, implement `navigationStackControllerSupportedInterfaceOrientations(_:)` or `navigationStackControllerPreferredInterfaceOrientationForPresentation(_:)`. Returning `nil` preserves UIKit's policy. Call the inherited `setNeedsUpdateOfSupportedInterfaceOrientations()` when your supported orientations change.

## Configure gestures

Horizontal content swipes navigate back and forward. The gesture recognizer respects right-to-left layout and gives nested horizontal scroll views priority while they can scroll in the requested direction.

```swift
navigation.allowsBackForwardNavigationGestures = true
```

Gestures are enabled by default. The swipe completion distance, maximum width fraction, and velocity projection duration control whether a swipe finishes. UIKit owns transition timing and appearance.

## Runtime dependency

> Warning: The UIKit implementation relies on undocumented APIs and runtime behavior, so extra care is needed before using it in App Store-bound projects.

The implementation uses UIKit's private `_UINavigationParallaxTransition` animator to preserve native overlap, adaptive corner clipping, shading, and shadow. An Objective-C runtime target resolves its class and selectors from encoded byte arrays and returns the native object so UIKit can use its internal transition protocols.

This behavior depends on the OS implementation. Missing runtime entry points raise an exception; an incompatible ABI change can cause a runtime failure. There is no substitute animator. Encoding private names does not make these APIs documented or stable.

The library reserves `UINavigationController.delegate` for this integration. Assign `navigationStackDelegate` for application callbacks; replacement of the native delegate is rejected even through a base-class reference.
