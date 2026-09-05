#if canImport(UIKit)
import OSLog
import UIKit

@MainActor
final class NavigationStackAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let operation: UINavigationController.Operation
    private let duration: TimeInterval
    private let parallaxFactor: CGFloat
    private let reducesMotion: Bool

    init(operation: UINavigationController.Operation, duration: TimeInterval, parallaxFactor: CGFloat) {
        self.operation = operation
        self.duration = duration
        self.parallaxFactor = parallaxFactor
        self.reducesMotion = unsafe UIAccessibility.isReduceMotionEnabled
    }

    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        reducesMotion ? min(duration, 0.2) : duration
    }

    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        guard let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to),
              let toController = transitionContext.viewController(forKey: .to) else {
            Logger(subsystem: "NavigationStackController", category: "Transition")
                .error("Navigation transition context did not provide its source and destination views.")
            transitionContext.completeTransition(false)
            return
        }

        let container = transitionContext.containerView
        let destinationFrame = transitionContext.finalFrame(for: toController)
        let sourceCenter = fromView.center
        let sourceAlpha = fromView.alpha
        let destinationAlpha = toView.alpha
        let destinationCenter = CGPoint(x: destinationFrame.midX, y: destinationFrame.midY)
        toView.bounds.size = destinationFrame.size
        toView.center = destinationCenter

        let isPop = operation == .pop
        if isPop {
            container.insertSubview(toView, belowSubview: fromView)
        } else {
            container.addSubview(toView)
        }
        toView.layoutIfNeeded()

        let fades = reducesMotion || operation == .none
        let direction: CGFloat = container.effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1
        let travel = container.bounds.width * direction
        let background = isPop ? toView : fromView
        let foreground = isPop ? fromView : toView
        let dimmingView = UIView(frame: background.bounds)
        dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimmingView.backgroundColor = .black
        dimmingView.isUserInteractionEnabled = false
        dimmingView.alpha = fades ? 0 : (isPop ? 0.14 : 0)
        background.addSubview(dimmingView)

        if fades {
            toView.alpha = 0
        } else if isPop {
            toView.center.x -= travel * parallaxFactor
        } else {
            toView.center.x += travel
        }

        let shadowView = UIView(frame: foreground.frame)
        shadowView.isUserInteractionEnabled = false
        shadowView.layer.shadowColor = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = fades ? 0 : 0.18
        shadowView.layer.shadowRadius = 8
        shadowView.layer.shadowOffset = .zero
        shadowView.layer.shadowPath = UIBezierPath(rect: shadowView.bounds).cgPath
        container.insertSubview(shadowView, belowSubview: foreground)

        UIView.animate(
            withDuration: transitionContext.isAnimated ? transitionDuration(using: transitionContext) : 0,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            if fades {
                fromView.alpha = 0
                toView.alpha = destinationAlpha
            } else if isPop {
                fromView.center.x = sourceCenter.x + travel
                toView.center = destinationCenter
                dimmingView.alpha = 0
            } else {
                fromView.center.x = sourceCenter.x - travel * self.parallaxFactor
                toView.center = destinationCenter
                dimmingView.alpha = 0.14
            }
            shadowView.center = foreground.center
        } completion: { _ in
            fromView.center = sourceCenter
            fromView.alpha = sourceAlpha
            toView.center = destinationCenter
            toView.alpha = destinationAlpha
            dimmingView.removeFromSuperview()
            shadowView.removeFromSuperview()
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
    }
}
#endif
