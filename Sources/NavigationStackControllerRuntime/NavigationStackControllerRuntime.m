#import "NavigationStackControllerRuntime.h"
#import <objc/runtime.h>

// Volatile reads prevent optimized builds from folding the encoded names back into plaintext.
static NSString *decodeRuntimeName(const volatile uint8_t *encodedBytes, size_t length)
{
    NSMutableData *data = [NSMutableData dataWithLength:length];
    uint8_t *decodedBytes = data.mutableBytes;
    for (size_t index = 0; index < length; ++index)
        decodedBytes[index] = encodedBytes[index] ^ 0xA7;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

// init methods consume their receiver and return a retained object; an ordinary IMP cast loses that ARC contract.
typedef id (*AnimatorInitializer)(id __attribute__((ns_consumed)), SEL, UINavigationControllerOperation) __attribute__((ns_returns_retained));
typedef void (*DirectionSetter)(id, SEL, BOOL);

id<UIViewControllerAnimatedTransitioning> NSCMakeNavigationAnimator(UINavigationControllerOperation operation, UIUserInterfaceLayoutDirection layoutDirection)
{
    // _UINavigationParallaxTransition
    static const uint8_t encodedClassName[] = { 0xF8, 0xF2, 0xEE, 0xE9, 0xC6, 0xD1, 0xCE, 0xC0, 0xC6, 0xD3, 0xCE, 0xC8, 0xC9, 0xF7, 0xC6, 0xD5, 0xC6, 0xCB, 0xCB, 0xC6, 0xDF, 0xF3, 0xD5, 0xC6, 0xC9, 0xD4, 0xCE, 0xD3, 0xCE, 0xC8, 0xC9 };
    // initWithCurrentOperation:
    static const uint8_t encodedInitializer[] = { 0xCE, 0xC9, 0xCE, 0xD3, 0xF0, 0xCE, 0xD3, 0xCF, 0xE4, 0xD2, 0xD5, 0xD5, 0xC2, 0xC9, 0xD3, 0xE8, 0xD7, 0xC2, 0xD5, 0xC6, 0xD3, 0xCE, 0xC8, 0xC9, 0x9D };
    // _setShouldReverseLayoutDirection:
    static const uint8_t encodedDirectionSetter[] = { 0xF8, 0xD4, 0xC2, 0xD3, 0xF4, 0xCF, 0xC8, 0xD2, 0xCB, 0xC3, 0xF5, 0xC2, 0xD1, 0xC2, 0xD5, 0xD4, 0xC2, 0xEB, 0xC6, 0xDE, 0xC8, 0xD2, 0xD3, 0xE3, 0xCE, 0xD5, 0xC2, 0xC4, 0xD3, 0xCE, 0xC8, 0xC9, 0x9D };

    Class animatorClass = NSClassFromString(decodeRuntimeName(encodedClassName, sizeof(encodedClassName)));
    SEL initializerSelector = NSSelectorFromString(decodeRuntimeName(encodedInitializer, sizeof(encodedInitializer)));
    SEL directionSelector = NSSelectorFromString(decodeRuntimeName(encodedDirectionSetter, sizeof(encodedDirectionSetter)));
    if (!animatorClass) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                      reason:@"Required UIKit navigation animator class is unavailable."
                                    userInfo:nil];
    }

    id receiver = [animatorClass alloc];
    if (![receiver respondsToSelector:initializerSelector]) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                      reason:@"Required UIKit navigation animator entry points are unavailable."
                                    userInfo:nil];
    }

    // Resolve on the allocated receiver after Objective-C has initialized its class.
    AnimatorInitializer initialize = (AnimatorInitializer)[receiver methodForSelector:initializerSelector];
    id animator = initialize(receiver, initializerSelector, operation);
    if (![animator conformsToProtocol:@protocol(UIViewControllerAnimatedTransitioning)]
        || ![animator respondsToSelector:directionSelector]) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                      reason:@"UIKit navigation animator initialization did not produce an animator."
                                    userInfo:nil];
    }

    DirectionSetter setDirection = (DirectionSetter)[animator methodForSelector:directionSelector];
    setDirection(animator, directionSelector, layoutDirection == UIUserInterfaceLayoutDirectionRightToLeft);
    // Return the actual UIKit object so its private transition protocols remain visible to UINavigationController.
    return animator;
}
