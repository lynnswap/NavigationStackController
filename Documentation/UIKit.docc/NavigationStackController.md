# ``NavigationStackController``

Add back and forward history to a UIKit navigation controller.

## Overview

`NavigationStackController` subclasses `UINavigationController`, retaining forward pages and adding interactive overlapping transitions.

Requires Swift 6.3 or later and iOS 18.4 or later. Use the controller and its delegate on the main actor.

> Warning: The UIKit implementation relies on undocumented APIs and runtime behavior, so extra care is needed before using it in App Store-bound projects.

Start with <doc:UIKitIntegration> to host the controller in your application.

## Topics

### Integration

- <doc:UIKitIntegration>
- <doc:History>

### API reference

- ``NavigationStackController``
- ``NavigationStackControllerDelegate``
- ``NavigationStackOperation``
