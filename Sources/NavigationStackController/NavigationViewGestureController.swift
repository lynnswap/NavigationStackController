import AppKit

@MainActor
final class NavigationViewGestureController {
    private weak var navigationController: NavigationStackController?
    private lazy var swipeProgressTracker = NavigationSwipeProgressTracker(viewGestureController: self)

    init(navigationController: NavigationStackController) {
        self.navigationController = navigationController
    }

    func handleScrollWheel(_ event: NSEvent, ignoringHorizontalScrollViews: Bool = false) -> Bool {
        guard let navigationController else {
            return false
        }

        if swipeProgressTracker.isActive {
            return swipeProgressTracker.handleScrollWheel(event)
        }

        guard navigationController.allowsBackForwardNavigationGestures, event.hasPreciseScrollingDeltas, NSEvent.isSwipeTrackingFromScrollEventsEnabled else {
            return false
        }

        guard navigationController.canGoBack || navigationController.canGoForward else {
            return false
        }

        if !ignoringHorizontalScrollViews, navigationController.shouldDeferSwipeTrackingToHorizontalScrollView(for: event) {
            return false
        }

        return swipeProgressTracker.handleScrollWheel(event)
    }

    func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
        guard let navigationController else {
            return false
        }

        let wants = axis == .horizontal
            && navigationController.allowsBackForwardNavigationGestures
            && NSEvent.isSwipeTrackingFromScrollEventsEnabled
            && (navigationController.canGoBack || navigationController.canGoForward)
        return wants
    }

    func progressSign(for direction: NavigationStackDirection) -> CGFloat {
        guard let navigationController else {
            return 1
        }

        let isLeftToRight = navigationController.view.userInterfaceLayoutDirection == .leftToRight

        switch direction {
        case .push:
            return 1
        case .back:
            return isLeftToRight ? 1 : -1
        case .forward:
            return isLeftToRight ? -1 : 1
        }
    }

    func navigationDirection(forSwipeGestureAmount amount: CGFloat) -> NavigationStackDirection? {
        if amount > 0 {
            return progressSign(for: .back) > 0 ? .back : .forward
        }

        if amount < 0 {
            return progressSign(for: .back) < 0 ? .back : .forward
        }

        return nil
    }

    var totalSwipeDistance: CGFloat {
        navigationController?.swipeDistance ?? 1
    }

    var completionThreshold: CGFloat {
        guard let navigationController else {
            return 0.5
        }

        let distance = max(totalSwipeDistance, 1)
        return min(navigationController.swipeCompletionDistance / distance, navigationController.maximumSwipeCompletionThreshold)
    }

    var kineticProjectionDuration: TimeInterval {
        navigationController?.swipeKineticProjectionDuration ?? 0.3
    }

    var minimumAnimationDuration: TimeInterval {
        navigationController?.minimumSwipeAnimationDuration ?? 0.1
    }

    var maximumAnimationDuration: TimeInterval {
        navigationController?.maximumSwipeAnimationDuration ?? 0.4
    }

    var isTrackingSwipeGesture: Bool {
        swipeProgressTracker.isActive
    }

    func beginSwipeGesture(direction: NavigationStackDirection) -> Bool {
        let didBegin = navigationController?.beginSwipeGesture(direction: direction) ?? false
        return didBegin
    }

    func handleSwipeGesture(progress: CGFloat) {
        navigationController?.handleSwipeGesture(progress: progress)
    }

    func endSwipeGesture(committed: Bool, duration: TimeInterval, completion: @escaping @MainActor () -> Void) {
        guard let navigationController else {
            completion()
            return
        }

        navigationController.endSwipeGesture(committed: committed, duration: duration, completion: completion)
    }

    func finishActiveSwipeGesture(cancelled: Bool) -> Bool {
        return swipeProgressTracker.finishActiveSwipeGesture(cancelled: cancelled)
    }
}

struct NavigationSwipeStartClassifier {
    enum Decision: Equatable {
        case pending
        case start
        case cancel
    }

    var minimumHorizontalDistance: CGFloat = 10
    var verticalHysteresis: CGFloat = 1.2

    func decision(deltaX: CGFloat, deltaY: CGFloat) -> Decision {
        let horizontalDistance = abs(deltaX)
        let verticalDistance = abs(deltaY)

        if horizontalDistance >= minimumHorizontalDistance, horizontalDistance > verticalDistance * verticalHysteresis {
            return .start
        }

        if verticalDistance >= minimumHorizontalDistance, verticalDistance > horizontalDistance * verticalHysteresis {
            return .cancel
        }

        return .pending
    }
}

@MainActor
private final class NavigationSwipeProgressTracker {
    private enum State {
        case none
        case pending
        case swiping
        case animating
    }

    private struct VelocitySample {
        let time: TimeInterval
        let progress: CGFloat
    }

    private weak var viewGestureController: NavigationViewGestureController?
    private var state = State.none
    private var direction: NavigationStackDirection?
    private var cumulativeDeltaX: CGFloat = 0
    private var cumulativeDeltaY: CGFloat = 0
    private var progress: CGFloat = 0
    private var averageVelocity: CGFloat = 0
    private var velocitySamples: [VelocitySample] = []
    private var forceCancelled = false

    private let classifier = NavigationSwipeStartClassifier()
    private let velocitySampleWindow: TimeInterval = 0.12
    private let minimumAnimationVelocity: CGFloat = 3.0

    init(viewGestureController: NavigationViewGestureController) {
        self.viewGestureController = viewGestureController
    }

    var isActive: Bool {
        state != .none
    }

    func finishActiveSwipeGesture(cancelled: Bool) -> Bool {
        switch state {
        case .none:
            return false
        case .pending:
            reset()
            return true
        case .swiping:
            finishSwipe(forcedCancelled: cancelled)
            return true
        case .animating:
            return true
        }
    }

    func handleScrollWheel(_ event: NSEvent) -> Bool {
        guard let viewGestureController else {
            return false
        }

        if state == .animating {
            return true
        }

        if event.phase.contains(.mayBegin) || event.phase.contains(.began) || (state == .none && event.phase.contains(.changed) && event.momentumPhase.isEmpty) {
            reset()
            state = .pending
        }

        guard state != .none else {
            return false
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            let wasSwiping = state == .swiping
            finishSwipe(forcedCancelled: event.phase.contains(.cancelled))
            return wasSwiping
        }

        cumulativeDeltaX += event.scrollingDeltaX
        cumulativeDeltaY += event.scrollingDeltaY

        if state == .pending {
            switch classifier.decision(deltaX: cumulativeDeltaX, deltaY: cumulativeDeltaY) {
            case .pending:
                if !event.momentumPhase.isEmpty {
                    reset()
                    return false
                }
                return true
            case .cancel:
                reset()
                return false
            case .start:
                guard let direction = viewGestureController.navigationDirection(forSwipeGestureAmount: cumulativeDeltaX) else {
                    reset()
                    return false
                }

                guard viewGestureController.beginSwipeGesture(direction: direction) else {
                    reset()
                    return false
                }

                self.direction = direction
                state = .swiping
            }
        }

        guard state == .swiping, let direction else {
            return true
        }

        let signedDistance = cumulativeDeltaX * viewGestureController.progressSign(for: direction)
        let progress = min(max(signedDistance / viewGestureController.totalSwipeDistance, 0), 1)
        updateProgress(progress)
        viewGestureController.handleSwipeGesture(progress: progress)

        if !event.momentumPhase.isEmpty {
            finishSwipe(forcedCancelled: event.momentumPhase.contains(.cancelled))
        }

        return true
    }

    private func updateProgress(_ newProgress: CGFloat) {
        progress = newProgress

        let now = CACurrentMediaTime()
        velocitySamples.append(VelocitySample(time: now, progress: newProgress))
        velocitySamples.removeAll { now - $0.time > velocitySampleWindow }

        guard let firstSample = velocitySamples.first, let lastSample = velocitySamples.last, lastSample.time > firstSample.time else {
            averageVelocity = 0
            return
        }

        averageVelocity = (lastSample.progress - firstSample.progress) / (lastSample.time - firstSample.time)
    }

    private func finishSwipe(forcedCancelled: Bool) {
        forceCancelled = forceCancelled || forcedCancelled

        guard state == .swiping, let viewGestureController else {
            reset()
            return
        }

        let projectedProgress = progress + averageVelocity * viewGestureController.kineticProjectionDuration
        let cancelled = forceCancelled || projectedProgress < viewGestureController.completionThreshold
        let duration = animationDuration(cancelled: cancelled)
        state = .animating
        viewGestureController.endSwipeGesture(committed: !cancelled, duration: duration) { [weak self] in
            self?.reset()
        }
    }

    private func animationDuration(cancelled: Bool) -> TimeInterval {
        guard let viewGestureController else {
            return 0.2
        }

        let targetProgress: CGFloat = cancelled ? 0 : 1
        let remainingDistance = abs(targetProgress - progress)
        let velocity = max(abs(averageVelocity), minimumAnimationVelocity)
        let duration = TimeInterval(remainingDistance / velocity)

        return min(max(duration, viewGestureController.minimumAnimationDuration), viewGestureController.maximumAnimationDuration)
    }

    private func reset() {
        state = .none
        direction = nil
        cumulativeDeltaX = 0
        cumulativeDeltaY = 0
        progress = 0
        averageVelocity = 0
        velocitySamples.removeAll()
        forceCancelled = false
    }
}
