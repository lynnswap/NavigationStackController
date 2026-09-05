# Contributing

Use these commands to validate library changes, build the documentation, and run the native example. Select Xcode with Swift 6.3 or later before running them.

## Tests

Run the AppKit regression suite:

```sh
swift test
```

Run UIKit tests with an installed Simulator:

```sh
./Tools/test-uikit.sh 'platform=iOS Simulator,name=iPhone 17'
```

The script creates a temporary standalone package context because the example workspace's dependency scheme does not expose the package test action.

The separate consumer fixture imports the public library product:

```sh
cd Tools/UIKitConsumer
xcodebuild -scheme UIKitConsumer -testPlan UIKitConsumer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

The existing CI workflow also builds the Release sample and checks its private runtime references with `Tools/check-private-symbols.py`.

## Documentation

Keep individual API contracts in source documentation comments. Put behavior spanning multiple APIs in the platform catalogs under `Documentation/UIKit.docc` and `Documentation/AppKit.docc`. The site's DocC entry page lives in `Documentation/NavigationStackController.docc`. Keep the README focused on introduction and installation.

Build both UIKit and AppKit references into a new output directory:

```sh
./Tools/build-documentation.sh /tmp/navigation-stack-docs
python3 -m http.server 8000 --directory /tmp/navigation-stack-docs
```

Open [the local documentation](http://localhost:8000). Remove the generated output directory before rebuilding, or choose another path. For hosting under a repository path, pass it as the second argument:

```sh
./Tools/build-documentation.sh /tmp/navigation-stack-pages /NavigationStackController
```

The build uses generic destinations and does not boot a Simulator. It treats DocC warnings as errors and checks that authored public symbols have comments. Synthesized conformances without source locations are excluded from that comment check.

UIKit and AppKit references are built separately: their same-named APIs have different types and contracts. The site offers both under `uikit/` and `appkit/`.

The Deploy documentation workflow builds and validates documentation on `main` pushes, then publishes successful builds to GitHub Pages. It also supports manual runs from `main`. Pull requests do not run the documentation workflow. In repository Settings → Pages, the publishing source must be **GitHub Actions**. The hosted README link becomes available after the first successful deployment.

## Example app

Open `NavigationStackController.xcworkspace` and run **MiniApp** on iOS Simulator or My Mac.

The iOS example includes forward navigation, horizontal content scrolling, navigation-bar visibility, and layout-direction controls. The AppKit example has two independently navigable panes. If replacing a previously installed SwiftUI version of the example, reinstall it once to discard its old scene sessions.
