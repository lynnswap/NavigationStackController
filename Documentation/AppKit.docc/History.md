# Understanding history and notifications

Coordinate AppKit navigation controls with retained pages and display callbacks.

## Navigate through the same page instances

``NavigationStackController/viewControllers`` lists pages from the root through the current top page. ``NavigationStackController/forwardViewControllers`` lists future pages with the next page first.

Starting with `[A, B, C]`, going back produces `[A, B]` and forward history `[C]`. Going back again produces `[A]` and `[B, C]`. Going forward restores the same `B` instance and leaves `[C]` in forward history. Pushing a new page or replacing the stack clears forward history.

``NavigationStackController/popToRootViewController(animated:)`` preserves removed pages in their original visitation order.

Method return values describe the page or pages accepted for removal or restoration. They do not signal animation completion. `canGoBack` and `canGoForward` describe history availability, not whether a new request can start immediately.

## Retention and containment

The controller manages child containment for both back and forward pages. It installs only the visible page's view outside transitions. Pushing a new page or replacing the stack discards forward history and reconciles child containment.

Removing pages from history releases the library's references. Other references held by the application may keep those controllers alive.

## History and displayed pages

Programmatic navigation updates history before display notifications. Interactive navigation updates history when the swipe successfully finishes; cancellation preserves both stacks.

Before the view is loaded, navigation changes history without display callbacks. Loading the view sends display notifications for the current page with the `set` operation. There is no separate history-change notification.

The `willShow` callback announces the destination. The `didShow` callback reports the displayed page. After an interactive cancellation, `didShow` reports the original page and attempted ``NavigationStackOperation``, so that operation is not proof of a successful navigation.

## Requests while navigation is unavailable

Navigation requests during a transition or a `willShow` callback are ignored. A `didShow` callback can start another navigation.

Stack replacement requires a nonempty array; passing an empty array fails a precondition even while navigation is unavailable. Duplicate instances in a replacement and pushes of pages already in either history are ignored.

For exact return values and validation rules, see the method reference.
