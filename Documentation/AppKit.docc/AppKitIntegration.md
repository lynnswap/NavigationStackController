# Integrating with AppKit

Host a stack of AppKit pages in your application's window or split view.

## Create the navigation controller

Use ``NavigationStackController/init(rootViewController:)`` with an `NSViewController` page. The controller owns child containment for both back and forward history and installs only the visible page's view outside a transition.

```swift
import AppKit
import NavigationStackController

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = NSViewController()
        root.view = NSView()
        root.title = "Home"

        let navigation = NavigationStackController(rootViewController: root)
        let window = NSWindow(contentViewController: navigation)
        window.setContentSize(NSSize(width: 800, height: 600))
        window.title = "Navigation Example"

        let windowController = NSWindowController(window: window)
        self.windowController = windowController
        windowController.showWindow(nil)
    }
}
```

Retain and install your application delegate in your native AppKit entry point. Toolbars, menus, and window management belong to the host application. The navigation controller can also be a child in a split view or another container.

## Observe navigation

Assign your retained ``NavigationStackControllerDelegate`` to the controller's `delegate` property. The delegate reference is weak, and both display methods have default implementations.

The callbacks use `NSViewController` pages and include a ``NavigationStackOperation``. This delegate provides display notifications; it has no separate history-change callback. See <doc:History> for when the stack changes relative to display notifications.

## Configure transitions

Trackpad navigation is enabled by default through ``NavigationStackController/allowsBackForwardNavigationGestures``. Horizontal scroll views keep priority while they can scroll in the requested direction.

AppKit provides animation duration and parallax settings in addition to the swipe completion settings. Use `transitionDuration` for noninteractive transitions, and `minimumSwipeAnimationDuration` / `maximumSwipeAnimationDuration` for finishing a swipe. Set `parallaxFactor` to zero to disable background parallax.

The AppKit implementation retains forward pages as child controllers. Replacing the stack or pushing a new page discards forward history and reconciles child containment.
