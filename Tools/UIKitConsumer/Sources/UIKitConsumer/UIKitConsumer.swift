import NavigationStackController
import UIKit

public enum UIKitConsumer {
    public static func makeNavigationController() -> NavigationStackController {
        let root = UIViewController()
        root.title = "Library"
        root.navigationItem.prompt = "Choose a document"

        let navigation = NavigationStackController(rootViewController: root)
        navigation.allowsBackForwardNavigationGestures = true
        navigation.swipeCompletionDistance = 187.5
        navigation.maximumSwipeCompletionThreshold = 0.5
        navigation.swipeKineticProjectionDuration = 0.3
        return navigation
    }
}
