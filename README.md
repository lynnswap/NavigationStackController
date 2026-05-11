# NavigationStackController

`NavigationStackController` is an AppKit navigation container for `NSViewController` stacks.

It provides a UIKit-style back/forward history model for macOS apps, including optional trackpad swipe navigation inspired by Safari and `WKWebView`.

## Requirements

- macOS 15.0+
- Swift 6.2+
- AppKit

## Usage

```swift
import AppKit
import NavigationStackController

let rootViewController = RootViewController()
let navigationController = NavigationStackController(rootViewController: rootViewController)

navigationController.pushViewController(DetailViewController(), animated: true)
navigationController.goBack(animated: true)
navigationController.goForward(animated: true)
```

## Behavior

- `pushViewController(_:animated:)` pushes a new `NSViewController` and clears forward history.
- `goBack(animated:)` moves the current controller into forward history.
- `goForward(animated:)` restores the latest forward-history controller.
- `popViewController(animated:)` is an alias for `goBack(animated:)`.
- `popToRootViewController(animated:)` returns to the root controller and moves popped controllers into forward history.
- `allowsBackForwardNavigationGestures` enables horizontal trackpad swipe navigation.

The controller owns `NSViewController` containment and installs only the visible controller's view in its container.

## Delegate

Use `NavigationStackControllerDelegate` to observe visible-controller changes.

```swift
final class HostController: NSViewController, NavigationStackControllerDelegate {
    func navigationStackController(
        _ controller: NavigationStackController,
        didShow viewController: NSViewController,
        operation: NavigationStackOperation,
        animated: Bool
    ) {
        // Update toolbar items, menus, or other navigation state.
    }
}
```

## Testing

```sh
swift test
```
