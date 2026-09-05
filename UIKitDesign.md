# UIKit implementation contract

The user approved UIKit support using UINavigationController, mandatory Safari-style overlap and bidirectional gesture navigation, and explicitly selected the name NavigationStackController. Breaking changes are allowed. This committed implementation brief is temporary; its public contract will live in README and doc comments before delivery.

## Scope and owners

One existing SwiftPM product/target NavigationStackController. Swift 6.3, macOS 15.4+, iOS 18.4+. Keep existing AppKit behavior; gate AppKit-specific implementation and tests. UIKit uses final @MainActor NavigationStackController: UINavigationController. Do not add a generic public history model or mirror UINavigationController.viewControllers.

UINavigationController owns back/current stack, containment, lifecycle and bars. NavigationStackController owns forward history (next item first), operation admission and pending operation intent. Native completion confirms forward-history changes; cancellation leaves them unchanged. The internal animator owns transient views and visual cleanup. The gesture controller owns pan recognition and its active interaction. Native edge/content pop recognizers are disabled by the library so a single pan owner handles back/forward. User delegate display/orientation callbacks remain usable through internal delegation; library owns the animation/interaction callbacks.

## Public UIKit surface

Existing UINavigationController initializers and stack methods remain available. New surface:
- weak navigationStackDelegate: NavigationStackControllerDelegate?
- forwardViewControllers: [UIViewController] { get }, next first
- canGoBack: Bool { get }, canGoForward: Bool { get }, isTransitioning: Bool { get }
- allowsBackForwardNavigationGestures: Bool = true
- transitionDuration: TimeInterval = 0.25, parallaxFactor: CGFloat = 0.28
- swipeCompletionDistance: CGFloat = 187.5, maximumSwipeCompletionThreshold: CGFloat = 0.5
- swipeKineticProjectionDuration: TimeInterval = 0.3
- goBack(animated: Bool) -> UIViewController? (outgoing, like native pop)
- goForward(animated: Bool) -> UIViewController? (restored)
- clearForwardHistory()
- pop, popToViewController, popToRoot retain popped controllers for forward in visitation order; new push and set clear forward after successful completion.
- inherited viewControllers assignment is equivalent to nonanimated set, including same-top replacements.
- invalid duplicate / already-parented new input is ignored; empty set is ignored (empty initializer remains native-valid); lifecycle/busy/reentrant commands are normal no-op.
- navigationStackDelegate has willShow/didShow matching current protocol but UIViewController arguments, plus navigationStackControllerDidChangeHistory(_:), all default implementations.

A pending operation carries only prior stack needed for the in-flight transaction, intended action and optional interaction driver; this is transient context, not a second live stack. Set/new push/forward distinguished at entry. Standard back must be reconciled via native transition hooks, not presumed to always enter pop override. Native delegates may reenter; admission closes before willShow.

## Animator and gesture worker API

Files: Sources/NavigationStackController/UIKit/NavigationStackAnimator.swift and NavigationStackGestureController.swift only. Gate whole files with #if canImport(UIKit).

Internal @MainActor final NavigationStackAnimator: NSObject, UIViewControllerAnimatedTransitioning:
init(operation: UINavigationController.Operation, duration: TimeInterval, parallaxFactor: CGFloat).
Use documented transition context views/container/frames, directional RTL-aware overlap/parallax, temporary shadow/dim as useful, completeTransition(!transitionWasCancelled) exactly once, restore transforms/alpha on cancellation and completion, respect Reduce Motion. No history callbacks.

Internal @MainActor final NavigationStackGestureController: NSObject, UIGestureRecognizerDelegate:
init(navigationController: NavigationStackController).
func install() // idempotently attaches its pan to nav.view and disables native back recognizers (iOS26 content recognizer availability)
func setEnabled(_ enabled: Bool) // disable during active gesture cancels through normal recognizer lifecycle.
Root provides beginInteractiveNavigation(_ operation: NavigationStackOperation) -> UIPercentDrivenInteractiveTransition? and public properties above.
Direction .back or .forward chosen from initial horizontal velocity and layout direction. Use UIView width; preserve selected direction through reversal; progress clamp [0,1]. Project terminal velocity using public distance/threshold/projection properties, then finish/cancel the returned driver. Do not use native private targets/selectors.
At gesture begin, defer to a hit-tested nested UIScrollView when it can scroll in requested direction, respecting adjustedContentInset. Explicitly handle horizontal dominance and RTL. Use public recognizer failure arbitration as needed; investigate meaning in primary Apple docs.
Worker may add internal pure helpers for its own calculations and meaningful focused tests in Tests/NavigationStackControllerTests/UIKitGestureTests.swift, but must not write controller/history tests.

## Root implementation and validation

Root owns manifest, shared operation enum, AppKit gates, UIKit NavigationStackController.swift and internal delegate/history implementation, README and integration validation. UIKit native history tests must exercise real UINavigationController methods including same-top replacement, pop-to ordering, standard callback forwarding and reentrant no-op. Interaction tests must run actual UIKit transition completion/cancellation, and gesture smoke verification should cover both directions, RTL and nested horizontal scroll.

Use Xcode tools for files visible in Xcode navigator. Worker opens its own isolated worktree Package.swift in Xcode and resolves that window; do not write root checkout via Xcode. Before edits: pwd, git status --short, git branch --show-current. Each worker commits only its assigned files to its dedicated branch. No push, PR, CI changes, history rewrite, simulator shutdown of user devices.

## Design decisions and measurements

Baseline: two AppKit source files, 1106 + 333 lines, one product/target, no UIKit implementation. Existing source uses AppKit throughout; platform axis is isolated at files, shared operation enum extracted. Current public declaration count and exact source baseline are available at 2d1ad9f568ec4b64f1687c6f276f544208865915. No existing AppKit owner migration is needed to add the second platform. The new consumer is a UIKit app using the actual library product, not @testable-only fixtures.

Rejected: UIPageViewController because mandatory overlapping navigation semantics require custom transitions; custom UIViewController containment because UINavigationController provides required public animation/interaction extension points; mirror history + native stack because it creates competing owners. No package split because there is no independent distribution/dependency boundary.

Escalate if UIKit callback behavior contradicts the history/commit contract, or APIs/owner boundaries need changes. Do not add timing workarounds, silent fallback or guessed preconditions. Preserve user inputs as normal event-driven no-ops during transitions.

## Delivery

Commit green checkpoints on codex/uikit-navigation-stack; integrate worker committed branches. Run macOS regression tests (README swift test), xcodebuild UIKit tests on named test simulator, external consumer build/link, and codex-review. Remove this brief from delivered tree after contracts are documented; preserve Why in commits.
