import AppKit

@MainActor
final class NavigationViewGestureController {
    private weak var navigationController: NavigationStackController?
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
            return false
        }

        guard event.phase.contains(.began), abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else {
            return false
        }

        let direction = navigationController.navigationDirection(forHorizontalDelta: event.scrollingDeltaX)
        guard navigationController.canBeginSwipeGesture(in: direction) else {
            return false
        }

        swipeProgressTracker.track(event: event, direction: direction)
        return true
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

        event.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount], dampenAmountThresholdMin: minProgress, max: maxProgress) { [weak self] amount, phase, isComplete, stop in
            guard let self, let viewGestureController = self.viewGestureController else {
                stop.pointee = true
                return
            }

            guard !didCompleteSwipe else {
                stop.pointee = true
                return
            }

            let progress = min(max(amount * sign, 0), 1)

            if phase.contains(.began), self.state == .pending {
                guard viewGestureController.beginSwipeGesture(direction: direction) else {
                    stop.pointee = true
                    self.reset()
                    return
                }
                self.state = .swiping
            } else if self.state == .pending, progress > 0 {
                guard viewGestureController.beginSwipeGesture(direction: direction) else {
                    stop.pointee = true
                    self.reset()
                    return
                }
                self.state = .swiping
            }

            if self.state == .swiping {
                self.updateProgress(progress)
                viewGestureController.handleSwipeGesture(progress: progress)
            }

            if phase.contains(.cancelled) {
                self.forceCancelled = true
            }

            if isComplete {
                didCompleteSwipe = true
                stop.pointee = true
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
