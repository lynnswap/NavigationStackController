#if os(macOS)
import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
withExtendedLifetime(delegate) {
    application.run()
}
#elseif canImport(UIKit)
import UIKit

unsafe UIApplicationMain(
    CommandLine.argc,
    CommandLine.unsafeArgv,
    nil,
    NSStringFromClass(AppDelegate.self)
)
#endif
