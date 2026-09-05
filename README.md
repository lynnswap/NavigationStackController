# NavigationStackController

A navigation container with back/forward history for UIKit and AppKit.

On iOS, `NavigationStackController` subclasses `UINavigationController` and adds retained forward history and overlapping, interactive transitions. On macOS, it contains `NSViewController` pages and supports trackpad swipe navigation.

## Requirements

- Swift 6.3+
- iOS 18.4+ or macOS 15.4+

## UIKit

```swift
import UIKit
import NavigationStackController

let navigation = NavigationStackController(
    rootViewController: HomeViewController()
)

navigation.pushViewController(DetailViewController(), animated: true)
navigation.goBack(animated: true)
navigation.goForward(animated: true)
```

Use the controller as a window's root view controller, inside a tab or split view controller, or as a child of your own container. UIKit continues to manage containment, each page's `navigationItem`, and the navigation bar. Hide the bar with the standard `setNavigationBarHidden(_:animated:)` API.

Horizontal content swipes navigate in both directions. The gestures respect right-to-left layout and give nested horizontal scroll views priority when those views can scroll in the requested direction. UIKit's navigation animator owns the overlapping pages, adaptive corner clipping, shading, shadow, and transition timing.

```swift
navigation.allowsBackForwardNavigationGestures = true // Default
```

The UIKit implementation uses the private `_UINavigationParallaxTransition` class, also used by WebKit for swipe navigation. A small Objective-C implementation target resolves the class and selectors from XOR-encoded byte arrays at runtime, then returns the native animator so UIKit can use its internal transition protocols. Private names are not stored as plaintext runtime references in the compiled artifact; `Tools/check-private-symbols.py` checks Release artifacts in CI. This depends on undocumented UIKit behavior; missing runtime entry points raise an exception and incompatible ABI changes can cause a runtime failure. There is no substitute animator. The `transitionDuration` and `parallaxFactor` settings apply only to the AppKit implementation.

The library owns the native navigation delegate and back gesture recognizers. Use `navigationStackDelegate` for notifications; replacing `UINavigationController.delegate` is unsupported and rejected even through a base-class reference.

```swift
@MainActor
final class NavigationObserver: NavigationStackControllerDelegate {
    func navigationStackControllerDidChangeHistory(
        _ controller: NavigationStackController
    ) {
        // Update Back / Forward controls from canGoBack and canGoForward.
    }

    func navigationStackController(
        _ controller: NavigationStackController,
        didShow viewController: UIViewController,
        operation: NavigationStackOperation,
        animated: Bool
    ) {
        // An interactive cancellation reports the original page.
    }
}

let observer = NavigationObserver() // Retain the observer in your host.
navigation.navigationStackDelegate = observer
```

Delegate references are weak. All delegate methods have default implementations. Display notifications describe presentation; `navigationStackControllerDidChangeHistory` describes successful history changes, including changes made before the view is displayed.

Implement `navigationStackControllerSupportedInterfaceOrientations(_:)` and `navigationStackControllerPreferredInterfaceOrientationForPresentation(_:)` to customize orientation policy without replacing the internal navigation delegate. Both return optional values; the default `nil` preserves UIKit's native policy. When the supported orientations change, use the inherited `setNeedsUpdateOfSupportedInterfaceOrientations()` method to request reevaluation. Navigation requests made inside these callbacks are ignored, just as they are inside display/history notifications.

## History behavior

- `viewControllers` contains the root through the current top controller.
- `forwardViewControllers.first` is the next controller that `goForward(animated:)` restores.
- A new push or stack replacement clears forward history.
- `goBack(animated:)` and `popViewController(animated:)` move the top controller into forward history.
- `goForward(animated:)` restores the same controller instance and preserves the remaining forward history.
- On UIKit, `popToViewController(_:animated:)` and `popToRootViewController(animated:)` preserve removed controllers in their original visitation order.
- UIKit forward controllers are strongly retained but no longer children of the navigation controller. `clearForwardHistory()` releases the library's references. If another container adopts the next forward controller, `canGoForward` becomes false and both forward entry points ignore the request until that controller is detached; later history entries are not skipped.
- Interactive cancellation preserves forward history. UIKit's native stack can reflect the tentative destination while a transition is active.
- On UIKit, `isTransitioning` indicates that a new navigation request cannot start. Requests during a transition or delegate notification are ignored.
- On UIKit, duplicate controller instances, already-parented new controllers, and empty stack replacements are ignored. Use forward navigation to revisit a controller already in forward history.

Navigation method return values indicate which controller was accepted for removal or restoration; they do not indicate animation completion. A nonanimated UIKit request may also deliver display notifications during a later layout pass.

## AppKit

```swift
import AppKit
import NavigationStackController

let navigation = NavigationStackController(
    rootViewController: RootViewController()
)
navigation.pushViewController(DetailViewController(), animated: true)
navigation.goBack(animated: true)
navigation.goForward(animated: true)
```

The AppKit controller owns child containment for back and forward history and installs only the visible page's view outside transitions. `allowsBackForwardNavigationGestures` enables trackpad navigation.

Assign the AppKit `NavigationStackControllerDelegate` to `navigation.delegate`. Its `willShow` and `didShow` methods use `NSViewController` arguments and include the navigation operation. Toolbars and menus remain part of the host application.

## Example app

Open `NavigationStackController.xcworkspace` and run the **MiniApp** scheme on an iPhone / iPad Simulator or on My Mac. When replacing an installed SwiftUI version of this demo, reinstall the demo once to discard its old scene sessions.

The example starts directly through UIKit or AppKit from `main.swift`. On iOS, `AppDelegate` selects the scene configuration and `SceneDelegate` owns a `UIWindow` with the navigation controller as its root. On macOS, `AppDelegate` owns an `NSWindowController` and displays the split navigation controller directly.

The UIKit example includes new-page and forward actions, horizontal scrolling content, navigation-bar visibility, and layout-direction controls. The AppKit example provides two independently navigable panes.

## Testing

Run AppKit regression tests:

```sh
swift test
```

Run the UIKit history, gesture, and interactive-transition tests on an available Simulator:

```sh
./Tools/test-uikit.sh 'platform=iOS Simulator,name=iPhone 17'
```

This script creates a temporary standalone package context, because the example app's workspace exposes a dependency scheme without the package test action.

The separate consumer fixture imports the actual public library product:

```sh
cd Tools/UIKitConsumer
xcodebuild -scheme UIKitConsumer -testPlan UIKitConsumer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
