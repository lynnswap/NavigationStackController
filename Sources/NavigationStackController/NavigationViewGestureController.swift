import AppKit

@MainActor
final class NavigationViewGestureController {
    private weak var navigationController: NavigationStackController?
    private lazy var swipeProgressTracker = NavigationSwipeProgressTracker(viewGestureController: self)
    private lazy var manualSwipeProgressTracker = NavigationManualSwipeProgressTracker(viewGestureController: self)
    private var needsManualSwipeTracking = false

    init(navigationController: NavigationStackController) {
        self.navigationController = navigationController
    }

    func handleScrollWheel(_ event: NSEvent) -> Bool {
        guard let navigationController else {
            return false
        }

        if manualSwipeProgressTracker.isActive {
            return manualSwipeProgressTracker.handleScrollWheel(event)
        }

        if swipeProgressTracker.isActive {
            return true
        }

        guard navigationController.allowsBackForwardNavigationGestures, event.hasPreciseScrollingDeltas, NSEvent.isSwipeTrackingFromScrollEventsEnabled else {
            return false
        }

        guard let dampenThresholds = swipeTrackingDampenThresholds else {
            return false
        }

        if usesManualSwipeTracking {
            return manualSwipeProgressTracker.handleScrollWheel(event)
        }

        guard event.phase.contains(.mayBegin) || event.phase.contains(.began) else {
            return false
        }

        if let initialDirection = navigationDirection(forSwipeGestureAmount: event.scrollingDeltaX), !navigationController.canBeginSwipeGesture(in: initialDirection) {
            return false
        }

        swipeProgressTracker.track(event: event, dampenThresholds: dampenThresholds)
        return true
    }

    private var usesManualSwipeTracking: Bool {
        needsManualSwipeTracking || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    func enableManualSwipeTracking() {
        needsManualSwipeTracking = true
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

    var swipeTrackingDampenThresholds: (min: CGFloat, max: CGFloat)? {
        guard let navigationController else {
            return nil
        }

        var min: CGFloat = 0
        var max: CGFloat = 0

        if navigationController.canGoBack {
            includeSwipeTrackingDirection(.back, min: &min, max: &max)
        }

        if navigationController.canGoForward {
            includeSwipeTrackingDirection(.forward, min: &min, max: &max)
        }

        guard min < 0 || max > 0 else {
            return nil
        }

        return (min, max)
    }

    private func includeSwipeTrackingDirection(_ direction: NavigationStackDirection, min: inout CGFloat, max: inout CGFloat) {
        if progressSign(for: direction) < 0 {
            min = -1
        } else {
            max = 1
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
        let didCancel = phase.contains(.cancelled) || phase.contains(.mayBegin)
        shouldFinish = isComplete || didCancel || phase.contains(.ended)
        isForcedCancellation = didCancel
    }
}

@MainActor
private final class NavigationManualSwipeProgressTracker {
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

    func handleScrollWheel(_ event: NSEvent) -> Bool {
        guard let viewGestureController else {
            return false
        }

        if state == .animating {
            return true
        }

        if event.phase.contains(.mayBegin) || event.phase.contains(.began) {
            reset()
            state = .pending
        }

        guard state != .none else {
            return false
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            finishSwipe(forcedCancelled: event.phase.contains(.cancelled))
            return true
        }

        cumulativeDeltaX += event.scrollingDeltaX
        cumulativeDeltaY += event.scrollingDeltaY

        if state == .pending {
            switch classifier.decision(deltaX: cumulativeDeltaX, deltaY: cumulativeDeltaY) {
            case .pending:
                return true
            case .cancel:
                reset()
                return false
            case .start:
                guard let direction = viewGestureController.navigationDirection(forSwipeGestureAmount: cumulativeDeltaX),
                      viewGestureController.beginSwipeGesture(direction: direction) else {
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
        direction = nil
        cumulativeDeltaX = 0
        cumulativeDeltaY = 0
        progress = 0
        averageVelocity = 0
        velocitySamples.removeAll()
        forceCancelled = false
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
    private var trackingCallbackCount = 0
    private var maximumObservedProgress: CGFloat = 0

    private let velocitySampleWindow: TimeInterval = 0.12
    private let minimumAnimationVelocity: CGFloat = 3.0
    private let stuckTrackingProgressThreshold: CGFloat = 0.02
    private let stuckTrackingCallbackThreshold = 4

    init(viewGestureController: NavigationViewGestureController) {
        self.viewGestureController = viewGestureController
    }

    var isActive: Bool {
        state != .none
    }

    func track(event: NSEvent, dampenThresholds: (min: CGFloat, max: CGFloat)) {
        guard state == .none, viewGestureController != nil else {
            return
        }

        state = .pending
        progress = 0
        averageVelocity = 0
        velocitySamples.removeAll()
        forceCancelled = false
        trackingCallbackCount = 0
        maximumObservedProgress = 0

        var direction: NavigationStackDirection?
        var didCompleteSwipe = false

        unsafe event.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount], dampenAmountThresholdMin: dampenThresholds.min, max: dampenThresholds.max) { [weak self] amount, phase, isComplete, stop in
            guard let self, let viewGestureController = self.viewGestureController else {
                unsafe stop.pointee = true
                return
            }

            guard !didCompleteSwipe else {
                unsafe stop.pointee = true
                return
            }

            trackingCallbackCount += 1
            let phaseDecision = NavigationSwipePhaseDecision(phase: phase, isComplete: isComplete)
            if phaseDecision.isForcedCancellation {
                self.forceCancelled = true
            }

            if direction == nil {
                direction = viewGestureController.navigationDirection(forSwipeGestureAmount: amount)
            }

            guard let direction else {
                if phaseDecision.shouldFinish {
                    didCompleteSwipe = true
                    unsafe stop.pointee = true
                    self.finishSwipe()
                }
                return
            }

            let progress = min(max(amount * viewGestureController.progressSign(for: direction), 0), 1)
            self.maximumObservedProgress = max(self.maximumObservedProgress, progress)

            if self.state == .pending, progress > 0 {
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

        if forceCancelled, maximumObservedProgress < stuckTrackingProgressThreshold, trackingCallbackCount >= stuckTrackingCallbackThreshold {
            viewGestureController.enableManualSwipeTracking()
        }

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
        trackingCallbackCount = 0
        maximumObservedProgress = 0
    }
}
