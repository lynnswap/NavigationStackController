#import "NavigationStackControllerRuntime.h"

// WebKit uses this UIKit animator for back/forward swipes. Returning the object itself preserves
// UIKit's private transition protocols, including its container clipping and navigation-bar coordination.
@interface _UINavigationParallaxTransition : NSObject <UIViewControllerAnimatedTransitioning>
- (instancetype)initWithCurrentOperation:(UINavigationControllerOperation)operation;
@end

id<UIViewControllerAnimatedTransitioning> NSCMakeNavigationAnimator(UINavigationControllerOperation operation)
{
    return [[_UINavigationParallaxTransition alloc] initWithCurrentOperation:operation];
}
