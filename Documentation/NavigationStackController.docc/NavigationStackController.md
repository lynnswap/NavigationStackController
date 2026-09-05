# NavigationStackController

Add back and forward navigation to native UIKit and AppKit applications.

@Metadata {
    @TechnologyRoot
}

## Overview

NavigationStackController provides a browser-style page history with interactive swipe transitions. Choose your platform to open its integration guides and API reference.

The package requires Swift 6.3 or later.

> Warning: This package relies on undocumented APIs and runtime behavior, so extra care is needed before using it in App Store-bound projects.

## Platforms

@Row {
    @Column {
        **[UIKit](/uikit/documentation/navigationstackcontroller/)**

        Extend `UINavigationController` with retained forward history and native overlapping transitions.

        iOS 18.4 and later.
    }

    @Column {
        **[AppKit](/appkit/documentation/navigationstackcontroller/)**

        Host `NSViewController` pages with back and forward history and trackpad swipe navigation.

        macOS 15.4 and later.
    }
}

## Source and examples

Find installation instructions and the native example application in the [GitHub repository](https://github.com/lynnswap/NavigationStackController).
