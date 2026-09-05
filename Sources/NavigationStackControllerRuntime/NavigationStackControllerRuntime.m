#import "NavigationStackControllerRuntime.h"

// WebKit uses this UIKit animator for back/forward swipes. Returning the object itself preserves
// UIKit's private transition protocols, including its container clipping and navigation-bar coordination.
@interface _UINavigationParallaxTransition : NSObject <UIViewControllerAnimatedTransitioning>
- (instancetype)initWithCurrentOperation:(UINavigationControllerOperation)operation;
- (void)_setShouldReverseLayoutDirection:(BOOL)reverse;
@end

id<UIViewControllerAnimatedTransitioning> NSCMakeNavigationAnimator(UINavigationControllerOperation operation, UIUserInterfaceLayoutDirection layoutDirection)
{
    _UINavigationParallaxTransition *animator = [[_UINavigationParallaxTransition alloc] initWithCurrentOperation:operation];
    [animator _setShouldReverseLayoutDirection:layoutDirection == UIUserInterfaceLayoutDirectionRightToLeft];
    return animator;
}
