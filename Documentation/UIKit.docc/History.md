# Understanding history and notifications

Coordinate UIKit navigation controls with retained pages and transition completion.

## Navigate through the same page instances

``NavigationStackController/viewControllers`` lists pages from the root through the current top page. ``NavigationStackController/forwardViewControllers`` lists future pages with the next page first.

Starting with `[A, B, C]`, going back produces `[A, B]` and forward history `[C]`. Going back again produces `[A]` and `[B, C]`. Going forward restores the same `B` instance and leaves `[C]` in forward history. Pushing a new page or replacing the stack clears forward history when navigation succeeds.

`popToViewController(_:animated:)` and `popToRootViewController(animated:)` preserve removed pages in their original visitation order.

Method return values describe the page or pages accepted for removal or restoration. They do not signal animation completion. `canGoBack` and `canGoForward` describe history availability, not whether a new request can start immediately.

## Retention and containment

UIKit manages the back stack and child containment. Outside an active transition, forward pages are strongly retained without being children of this navigation controller. During a forward transition, the restored page may already be a child while its removal from forward history is still pending.

Another container can adopt a detached forward page. Forward navigation then waits until the next page is detached again; later entries are not skipped.

`clearForwardHistory()` releases the library's forward references. Other references held by the application may keep those controllers alive.

## Committed history and displayed pages

UIKit may expose the tentative destination in its native back stack during a transition. Forward history is committed only when navigation succeeds. Interactive cancellation restores the original navigation state and preserves forward history.

`navigationStackControllerDidChangeHistory(_:)` reports committed navigation and explicit removal of nonempty forward history, including changes before the controller is displayed. Cancelled interactive transitions do not send this notification.

The `willShow` callback announces the destination. The `didShow` callback reports the page displayed after completion; cancellation reports the original page with the attempted ``NavigationStackOperation``. A change without presentation may not send display callbacks. Even a nonanimated request may deliver display callbacks during a later layout pass.

## Requests while navigation is unavailable

Navigation mutations are ignored during transitions and inside any delegate callback, including orientation callbacks. `isTransitioning` reports pending navigation or another active UIKit transition. Requests inside delegate callbacks remain unavailable even when this property is false.

Empty replacements, duplicate page instances, and replacements containing pages owned by another parent are ignored. A new push is ignored if its page already has a parent or is in either history.

For exact return values and validation rules, see the method reference.
