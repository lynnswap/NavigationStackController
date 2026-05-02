import AppKit

@MainActor
final class NavigationViewGestureController {
    private weak var navigationController: NavigationStackController?
    private let pendingSwipeTracker = NavigationPendingSwipeTracker()
    private lazy var swipeProgressTracker = NavigationSwipeProgressTracker(viewGestureController: self)

    init(navigationController: NavigationStackController) {
        self.navigationController = navigationController
    }

    func handleScrollWheel(_ event: NSEvent) -> Bool {
        guard let navigationController else {
            return false
        }

        if swipeProgressTracker.isActive {
            return true
        }

        guard navigationController.allowsBackForwardNavigationGestures, event.hasPreciseScrollingDeltas, NSEvent.isSwipeTrackingFromScrollEventsEnabled else {
            pendingSwipeTracker.reset()
            return false
        }

        switch pendingSwipeTracker.handle(event: event) {
        case .pending, .cancel:
            return false
        case .start(let horizontalDelta):
            let direction = navigationController.navigationDirection(forHorizontalDelta: horizontalDelta)
            guard navigationController.canBeginSwipeGesture(in: direction) else {
                return false
            }

            swipeProgressTracker.track(event: event, direction: direction)
            return true
        }
    }

    func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
        guard let navigationController else {
            return false
        }

        return axis == .horizontal
            && navigationController.allowsBackForwardNavigationGestures
            && (navigationController.canGoBack || navigationController.canGoForward)
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

    func beginSwipeGesture(direction: NavigationStackDirection) -> Bool {
        navigationController?.beginSwipeGesture(direction: direction) ?? false
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

struct NavigationSwipePhaseDecision: Equatable {
    let shouldFinish: Bool
    let isForcedCancellation: Bool

    init(phase: NSEvent.Phase, isComplete: Bool) {
        let didCancel = phase.contains(.cancelled)
        shouldFinish = isComplete || didCancel || phase.contains(.ended)
        isForcedCancellation = didCancel
    }
}

@MainActor
private final class NavigationPendingSwipeTracker {
    enum Decision {
        case pending
        case start(horizontalDelta: CGFloat)
        case cancel
    }

    private var cumulativeDeltaX: CGFloat = 0
    private var cumulativeDeltaY: CGFloat = 0
    private var isTracking = false
    private let classifier = NavigationSwipeStartClassifier()

    func handle(event: NSEvent) -> Decision {
        if event.phase.contains(.began) {
            reset()
            isTracking = true
        }

        guard isTracking else {
            return .cancel
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            reset()
            return .cancel
        }

        cumulativeDeltaX += event.scrollingDeltaX
        cumulativeDeltaY += event.scrollingDeltaY

        switch classifier.decision(deltaX: cumulativeDeltaX, deltaY: cumulativeDeltaY) {
        case .pending:
            return .pending
        case .start:
            let horizontalDelta = cumulativeDeltaX
            reset()
            return .start(horizontalDelta: horizontalDelta)
        case .cancel:
            reset()
            return .cancel
        }
    }

    func reset() {
        cumulativeDeltaX = 0
        cumulativeDeltaY = 0
        isTracking = false
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
    private var progress: CGFloat = 0
    private var averageVelocity: CGFloat = 0
    private var velocitySamples: [VelocitySample] = []
    private var forceCancelled = false

    private let velocitySampleWindow: TimeInterval = 0.12
    private let minimumAnimationVelocity: CGFloat = 3.0

    init(viewGestureController: NavigationViewGestureController) {
        self.viewGestureController = viewGestureController
    }

    var isActive: Bool {
        state != .none
    }

    func track(event: NSEvent, direction: NavigationStackDirection) {
        guard state == .none, let viewGestureController else {
            return
        }

        state = .pending
        progress = 0
        averageVelocity = 0
        velocitySamples.removeAll()
        forceCancelled = false

        let sign = viewGestureController.progressSign(for: direction)
        let minProgress: CGFloat = sign < 0 ? -1 : 0
        let maxProgress: CGFloat = sign > 0 ? 1 : 0
        var didCompleteSwipe = false

        unsafe event.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount], dampenAmountThresholdMin: minProgress, max: maxProgress) { [weak self] amount, phase, isComplete, stop in
            guard let self, let viewGestureController = self.viewGestureController else {
                unsafe stop.pointee = true
                return
            }

            guard !didCompleteSwipe else {
                unsafe stop.pointee = true
                return
            }

            let progress = min(max(amount * sign, 0), 1)

            if phase.contains(.began), self.state == .pending {
                guard viewGestureController.beginSwipeGesture(direction: direction) else {
                    unsafe stop.pointee = true
                    self.reset()
                    return
                }
                self.state = .swiping
            } else if self.state == .pending, progress > 0 {
                guard viewGestureController.beginSwipeGesture(direction: direction) else {
                    unsafe stop.pointee = true
                    self.reset()
                    return
                }
                self.state = .swiping
            }

            if self.state == .swiping {
                self.updateProgress(progress)
                viewGestureController.handleSwipeGesture(progress: progress)
            }

            let phaseDecision = NavigationSwipePhaseDecision(phase: phase, isComplete: isComplete)
            if phaseDecision.isForcedCancellation {
                self.forceCancelled = true
            }

            if phaseDecision.shouldFinish {
                didCompleteSwipe = true
                unsafe stop.pointee = true
                self.finishSwipe()
            }
        }
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

    private func finishSwipe() {
        guard state == .swiping, let viewGestureController else {
            reset()
            return
        }

        let cancelled = forceCancelled || shouldCancel()
        let duration = animationDuration(cancelled: cancelled)
        state = .animating

        viewGestureController.endSwipeGesture(committed: !cancelled, duration: duration) { [weak self] in
            self?.reset()
        }
    }

    private func shouldCancel() -> Bool {
        guard let viewGestureController else {
            return true
        }

        let projectedProgress = progress + averageVelocity * viewGestureController.kineticProjectionDuration
        return projectedProgress < viewGestureController.completionThreshold
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
        progress = 0
        averageVelocity = 0
        velocitySamples.removeAll()
        forceCancelled = false
    }
}
