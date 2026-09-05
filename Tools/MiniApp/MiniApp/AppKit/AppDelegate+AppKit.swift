#if os(macOS)
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var windowController: NSWindowController = {
        let window = NSWindow(contentViewController: DemoSplitViewController())
        window.title = "NavigationStackController"
        window.setContentSize(NSSize(width: 1_000, height: 650))
        window.contentMinSize = NSSize(width: 640, height: 400)
        window.center()
        return NSWindowController(window: window)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let application = NSApplication.shared
        installMainMenu(in: application)
        windowController.showWindow(nil)
        application.activate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            windowController.showWindow(nil)
        }
        return true
    }

    private func installMainMenu(in application: NSApplication) {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "MiniApp")
        applicationMenu.addItem(withTitle: "About MiniApp", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Hide MiniApp", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = applicationMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        applicationMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit MiniApp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        application.mainMenu = mainMenu
        application.windowsMenu = windowMenu
    }
}
#endif
