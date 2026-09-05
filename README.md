# NavigationStackController

A navigation container with back/forward history for UIKit and AppKit.

On iOS, it extends `UINavigationController` with retained forward history and overlapping, interactive transitions. On macOS, it hosts `NSViewController` pages with trackpad swipe navigation.

> [!WARNING]
> This package relies on undocumented APIs and runtime behavior, so extra care is needed before using it in App Store-bound projects.

## Requirements

- Swift 6.3+
- iOS 18.4+ or macOS 15.4+

## Installation

Add [NavigationStackController](https://github.com/lynnswap/NavigationStackController) as a Swift package dependency in Xcode, then add the **NavigationStackController** product to your application target.

## Quick start

```swift
import UIKit
import NavigationStackController

let navigation = NavigationStackController(rootViewController: UIViewController())
navigation.pushViewController(UIViewController(), animated: true)
navigation.goBack(animated: false)
navigation.goForward(animated: false)
```

Use the controller as your window's root controller or inside another UIKit container. On AppKit, import `AppKit` and use `NSViewController` pages with the same navigation methods.

## Documentation

See the [DocC documentation](https://lynnswap.github.io/NavigationStackController/) for platform integration, API references, history behavior, and delegate callbacks.

## Example app

Open `NavigationStackController.xcworkspace` and run the **MiniApp** scheme on an iPhone / iPad Simulator or on My Mac. The example uses native UIKit and AppKit application lifecycles.

For local documentation builds and regression tests, see [Contributing](CONTRIBUTING.md).
