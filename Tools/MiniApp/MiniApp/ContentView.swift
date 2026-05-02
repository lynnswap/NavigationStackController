//
//  ContentView.swift
//  MiniApp
//
//  Created by Kazuki Nakashima on 2026/05/02.
//

import AppKit
import SwiftUI
import NavigationStackController

struct ContentView: View {
    var body: some View {
        DemoSplitNavigationView()
            .ignoresSafeArea()
    }
}

private struct DemoSplitNavigationView: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> DemoSplitViewController {
        DemoSplitViewController()
    }

    func updateNSViewController(_ nsViewController: DemoSplitViewController, context: Context) {
    }
}

private final class DemoSplitViewController: NSSplitViewController, NSToolbarDelegate, NSToolbarItemValidation {
    private enum ToolbarItem {
        static let leftBack = NSToolbarItem.Identifier("DemoToolbar.LeftBack")
        static let leftForward = NSToolbarItem.Identifier("DemoToolbar.LeftForward")
        static let splitTrackingSeparator = NSToolbarItem.Identifier("DemoToolbar.SplitTrackingSeparator")
        static let rightBack = NSToolbarItem.Identifier("DemoToolbar.RightBack")
        static let rightForward = NSToolbarItem.Identifier("DemoToolbar.RightForward")
    }

    private let navigationToolbar = NSToolbar(identifier: "DemoNavigationToolbar")
    private let leftPane = DemoNavigationHostController()
    private let rightPane = DemoNavigationHostController()

    override func viewDidLoad() {
        super.viewDidLoad()

        splitView.isVertical = true
        splitView.dividerStyle = .thin

        leftPane.onNavigationStateChanged = { [weak self] in
            self?.navigationToolbar.validateVisibleItems()
        }
        rightPane.onNavigationStateChanged = { [weak self] in
            self?.navigationToolbar.validateVisibleItems()
        }

        addPane(leftPane)
        addPane(rightPane)
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        navigationToolbar.delegate = self
        navigationToolbar.displayMode = .iconOnly
        navigationToolbar.allowsUserCustomization = false
        view.window?.toolbar = navigationToolbar
        view.window?.toolbarStyle = .unified
        view.window?.titleVisibility = .hidden
        navigationToolbar.validateVisibleItems()
    }

    private func addPane(_ viewController: NSViewController) {
        let item = NSSplitViewItem(viewController: viewController)
        item.minimumThickness = 320
        addSplitViewItem(item)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItem.leftBack,
            ToolbarItem.leftForward,
            ToolbarItem.splitTrackingSeparator,
            ToolbarItem.rightBack,
            ToolbarItem.rightForward,
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItem.leftBack,
            ToolbarItem.leftForward,
            ToolbarItem.splitTrackingSeparator,
            ToolbarItem.rightBack,
            ToolbarItem.rightForward,
        ]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarItem.leftBack:
            return makeToolbarItem(identifier: itemIdentifier, label: "Left Back", symbolName: "chevron.left", action: #selector(goBackInLeftPane))
        case ToolbarItem.leftForward:
            return makeToolbarItem(identifier: itemIdentifier, label: "Left Forward", symbolName: "chevron.right", action: #selector(goForwardInLeftPane))
        case ToolbarItem.splitTrackingSeparator:
            return NSTrackingSeparatorToolbarItem(identifier: itemIdentifier, splitView: splitView, dividerIndex: 0)
        case ToolbarItem.rightBack:
            return makeToolbarItem(identifier: itemIdentifier, label: "Right Back", symbolName: "chevron.left", action: #selector(goBackInRightPane))
        case ToolbarItem.rightForward:
            return makeToolbarItem(identifier: itemIdentifier, label: "Right Forward", symbolName: "chevron.right", action: #selector(goForwardInRightPane))
        default:
            return nil
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case ToolbarItem.leftBack:
            return leftPane.canGoBack
        case ToolbarItem.leftForward:
            return leftPane.canGoForward
        case ToolbarItem.rightBack:
            return rightPane.canGoBack
        case ToolbarItem.rightForward:
            return rightPane.canGoForward
        default:
            return true
        }
    }

    private func makeToolbarItem(identifier: NSToolbarItem.Identifier, label: String, symbolName: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        item.target = self
        item.action = action
        return item
    }

    @objc private func goBackInLeftPane() {
        leftPane.goBack()
    }

    @objc private func goForwardInLeftPane() {
        leftPane.goForward()
    }

    @objc private func goBackInRightPane() {
        rightPane.goBack()
    }

    @objc private func goForwardInRightPane() {
        rightPane.goForward()
    }
}

private final class DemoNavigationHostController: NSViewController, NavigationStackControllerDelegate {
    var onNavigationStateChanged: (() -> Void)?

    private var navigationController: NavigationStackController!

    var canGoBack: Bool {
        navigationController?.canGoBack ?? false
    }

    var canGoForward: Bool {
        navigationController?.canGoForward ?? false
    }

    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let rootViewController = makePageViewController(number: 1)
        navigationController = NavigationStackController(rootViewController: rootViewController)
        navigationController.delegate = self
        navigationController.transitionDuration = 0.22
        navigationController.maximumSwipeCompletionThreshold = 0.42

        addChild(navigationController)
        view.addSubview(navigationController.view)
        navigationController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            navigationController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationController.view.topAnchor.constraint(equalTo: view.topAnchor),
            navigationController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        onNavigationStateChanged?()
    }

    func navigationStackController(_ controller: NavigationStackController, didShow viewController: NSViewController, operation: NavigationStackOperation, animated: Bool) {
        onNavigationStateChanged?()
    }

    private func makePageViewController(number: Int) -> DemoPageViewController {
        let viewController = DemoPageViewController(page: DemoPage(number: number))
        viewController.onPush = { [weak self] in
            self?.pushPage()
        }
        return viewController
    }

    private func pushPage() {
        let pageNumber = navigationController.viewControllers.count + 1
        navigationController.pushViewController(makePageViewController(number: pageNumber), animated: true)
        onNavigationStateChanged?()
    }

    func goBack() {
        navigationController.goBack(animated: true)
        onNavigationStateChanged?()
    }

    func goForward() {
        navigationController.goForward(animated: true)
        onNavigationStateChanged?()
    }
}

private struct DemoPage {
    let number: Int

    var title: String {
        "Page \(number)"
    }

    var address: String {
        "navigation://page/\(number)"
    }

    var backgroundColor: NSColor {
        let palette: [NSColor] = [
            NSColor(calibratedRed: 0.10, green: 0.34, blue: 0.45, alpha: 1.0),
            NSColor(calibratedRed: 0.55, green: 0.20, blue: 0.28, alpha: 1.0),
            NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.24, alpha: 1.0),
            NSColor(calibratedRed: 0.40, green: 0.28, blue: 0.58, alpha: 1.0),
            NSColor(calibratedRed: 0.62, green: 0.45, blue: 0.12, alpha: 1.0),
        ]

        return palette[(number - 1) % palette.count]
    }
}

private final class DemoPageViewController: NSViewController {
    var onPush: (() -> Void)?

    private let page: DemoPage

    init(page: DemoPage) {
        self.page = page
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let view = DemoClickablePageView()
        view.onClick = { [weak self] in
            self?.onPush?()
        }
        view.wantsLayer = true
        view.layer?.backgroundColor = page.backgroundColor.cgColor
        self.view = view

        let titleLabel = makeLabel(text: page.title, font: NSFont.systemFont(ofSize: 46, weight: .bold), alpha: 1.0)
        let addressLabel = makeLabel(text: page.address, font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium), alpha: 0.72)
        let titleStack = NSStackView(views: [titleLabel, addressLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .centerX
        titleStack.spacing = 10
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleStack)

        NSLayoutConstraint.activate([
            titleStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            titleStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 36),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -36),
        ])
    }

    private func makeLabel(text: String, font: NSFont, alpha: CGFloat) -> NSTextField {
        let textField = NSTextField(labelWithString: text)
        textField.font = font
        textField.textColor = NSColor.white.withAlphaComponent(alpha)
        textField.alignment = .center
        textField.lineBreakMode = .byTruncatingTail
        return textField
    }
}

private final class DemoClickablePageView: NSView {
    var onClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard super.hitTest(point) != nil else {
            return nil
        }

        return self
    }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }
}

#Preview {
    ContentView()
        .frame(minWidth: 900, minHeight: 520)
}
