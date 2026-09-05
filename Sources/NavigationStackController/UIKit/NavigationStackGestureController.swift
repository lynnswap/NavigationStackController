#if canImport(UIKit)
import UIKit

@MainActor
final class NavigationStackGestureController: NSObject, UIGestureRecognizerDelegate {
    private struct Interaction {
        let pan: NavigationStackPan
        let driver: UIPercentDrivenInteractiveTransition
    }

    private enum State {
        case idle
        case ready(NavigationStackPan)
        case active(Interaction)
    }

    private weak var navigationController: NavigationStackController?
    private weak var touchedView: UIView?
    private var state = State.idle
    private lazy var recognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = self
        recognizer.name = "NavigationStackController.backForward"
        return recognizer
    }()

    init(navigationController: NavigationStackController) {
        self.navigationController = navigationController
    }

    func install() {
        guard let navigationController else { return }
        let view: UIView = navigationController.view
        if recognizer.view !== view {
            view.addGestureRecognizer(recognizer)
        }
        navigationController.interactivePopGestureRecognizer?.isEnabled = false
        if #available(iOS 26.0, *) {
            navigationController.interactiveContentPopGestureRecognizer?.isEnabled = false
        }
        setEnabled(navigationController.allowsBackForwardNavigationGestures)
    }

    func setEnabled(_ enabled: Bool) {
        recognizer.isEnabled = enabled
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touchedView = touch.view
        guard let navigationController, let touchedView else { return false }
        return !touchedView.isDescendant(of: navigationController.navigationBar)
            && !touchedView.isDescendant(of: navigationController.toolbar)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        state = .idle
        guard let navigationController,
              navigationController.allowsBackForwardNavigationGestures,
              !navigationController.isTransitioning,
              let view = gestureRecognizer.view,
              let pan = NavigationStackPan(
                velocity: recognizer.velocity(in: view),
                width: view.bounds.width,
                layoutDirection: view.effectiveUserInterfaceLayoutDirection
              ),
              pan.operation == .back ? navigationController.canGoBack : navigationController.canGoForward else {
            return false
        }

        var ancestor = touchedView
        while let view = ancestor, view !== navigationController.view {
            if let scrollView = view as? UIScrollView,
               Self.canScroll(scrollView, horizontalDirection: pan.horizontalSign) {
                return false
            }
            ancestor = view.superview
        }

        state = .ready(pan)
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard let scrollView = otherGestureRecognizer.view as? UIScrollView,
              otherGestureRecognizer === scrollView.panGestureRecognizer,
              let view = gestureRecognizer.view else { return false }

        // Scroll views wait for our direction and boundary decision, so their bounce
        // recognizer cannot claim the touch before navigation gets a chance to begin.
        return scrollView.isDescendant(of: view)
    }

    static func canScroll(_ scrollView: UIScrollView, horizontalDirection: CGFloat) -> Bool {
        guard scrollView.isScrollEnabled, scrollView.panGestureRecognizer.isEnabled else { return false }
        let minimum = -scrollView.adjustedContentInset.left
        let maximum = scrollView.contentSize.width - scrollView.bounds.width
            + scrollView.adjustedContentInset.right
        guard maximum > minimum else { return false }
        return horizontalDirection > 0
            ? scrollView.contentOffset.x > minimum
            : scrollView.contentOffset.x < maximum
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard case let .ready(pan) = state else { return }
            state = .idle
            guard let driver = navigationController?.beginInteractiveNavigation(pan.operation) else { return }
            guard recognizer.isEnabled, recognizer.state == .began || recognizer.state == .changed else {
                driver.cancel()
                return
            }
            state = .active(Interaction(pan: pan, driver: driver))
            driver.update(pan.progress(translation: recognizer.translation(in: recognizer.view)))
        case .changed:
            guard case let .active(interaction) = state else { return }
            interaction.driver.update(
                interaction.pan.progress(translation: recognizer.translation(in: recognizer.view))
            )
        case .ended:
            guard case let .active(interaction) = state else {
                state = .idle
                return
            }
            state = .idle
            guard let navigationController else {
                interaction.driver.cancel()
                return
            }
            let translation = recognizer.translation(in: recognizer.view)
            interaction.driver.update(interaction.pan.progress(translation: translation))
            let completes = interaction.pan.completes(
                translation: translation,
                velocity: recognizer.velocity(in: recognizer.view),
                completionDistance: navigationController.swipeCompletionDistance,
                maximumThreshold: navigationController.maximumSwipeCompletionThreshold,
                projectionDuration: navigationController.swipeKineticProjectionDuration
            )
            if completes {
                interaction.driver.finish()
            } else {
                interaction.driver.cancel()
            }
        case .cancelled, .failed:
            let previousState = state
            state = .idle
            if case let .active(interaction) = previousState {
                interaction.driver.cancel()
            }
        case .possible:
            break
        @unknown default:
            break
        }
    }
}

struct NavigationStackPan {
    let operation: NavigationStackOperation
    let horizontalSign: CGFloat
    private let width: CGFloat

    init?(velocity: CGPoint, width: CGFloat, layoutDirection: UIUserInterfaceLayoutDirection) {
        guard width > 0, abs(velocity.x) > abs(velocity.y) else { return nil }
        horizontalSign = velocity.x > 0 ? 1 : -1
        self.width = width
        let backSign: CGFloat = layoutDirection == .rightToLeft ? -1 : 1
        operation = horizontalSign == backSign ? .back : .forward
    }

    func progress(translation: CGPoint) -> CGFloat {
        min(max(translation.x * horizontalSign / width, 0), 1)
    }

    func completes(
        translation: CGPoint,
        velocity: CGPoint,
        completionDistance: CGFloat,
        maximumThreshold: CGFloat,
        projectionDuration: TimeInterval
    ) -> Bool {
        let projectedDistance = (translation.x + velocity.x * projectionDuration) * horizontalSign
        let thresholdDistance = min(completionDistance, width * maximumThreshold)
        return projectedDistance > thresholdDistance
    }
}
#endif
