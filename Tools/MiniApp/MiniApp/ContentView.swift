//
//  ContentView.swift
//  MiniApp
//
//  Created by Kazuki Nakashima on 2026/05/02.
//

import AppKit
import SwiftUI
import NavigationStackController

private enum DemoPageContentStyle: Int {
    case centeredTitle
    case horizontalScroll

    var segmentLabel: String {
        switch self {
        case .centeredTitle:
            "Normal"
        case .horizontalScroll:
            "Scroll"
        }
    }
}

struct ContentView: View {
    private let contentStyle: DemoPageContentStyle
    private let initialPageCount: Int

    init() {
        contentStyle = .centeredTitle
        initialPageCount = 1
    }

    fileprivate init(contentStyle: DemoPageContentStyle, initialPageCount: Int = 1) {
        self.contentStyle = contentStyle
        self.initialPageCount = max(initialPageCount, 1)
    }

    var body: some View {
        DemoSplitNavigationView(contentStyle: contentStyle, initialPageCount: initialPageCount)
            .ignoresSafeArea()
    }
}

private struct DemoSplitNavigationView: NSViewControllerRepresentable {
    let contentStyle: DemoPageContentStyle
    let initialPageCount: Int

    func makeNSViewController(context: Context) -> DemoSplitViewController {
        DemoSplitViewController(contentStyle: contentStyle, initialPageCount: initialPageCount)
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
        static let contentStyle = NSToolbarItem.Identifier("DemoToolbar.ContentStyle")
    }

    private let navigationToolbar = NSToolbar(identifier: "DemoNavigationToolbar")
    private let leftPane: DemoNavigationHostController
    private let rightPane: DemoNavigationHostController
    private var contentStyle: DemoPageContentStyle
    private weak var contentStyleControl: NSSegmentedControl?

    init(contentStyle: DemoPageContentStyle = .centeredTitle, initialPageCount: Int = 1) {
        self.contentStyle = contentStyle
        leftPane = DemoNavigationHostController(contentStyle: contentStyle, initialPageCount: initialPageCount)
        rightPane = DemoNavigationHostController(contentStyle: contentStyle, initialPageCount: initialPageCount)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

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
        let window = unsafe view.window
        window?.toolbar = navigationToolbar
        window?.toolbarStyle = .unified
        window?.titleVisibility = .hidden
        navigationToolbar.validateVisibleItems()
    }

    private func addPane(_ viewController: NSViewController) {
        let item = NSSplitViewItem(viewController: viewController)
        item.minimumThickness = 320
        insertSplitViewItem(item, at: splitViewItems.count)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItem.leftBack,
            ToolbarItem.leftForward,
            ToolbarItem.splitTrackingSeparator,
            ToolbarItem.rightBack,
            ToolbarItem.rightForward,
            .flexibleSpace,
            ToolbarItem.contentStyle,
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItem.leftBack,
            ToolbarItem.leftForward,
            ToolbarItem.splitTrackingSeparator,
            ToolbarItem.rightBack,
            ToolbarItem.rightForward,
            .flexibleSpace,
            ToolbarItem.contentStyle,
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
        case ToolbarItem.contentStyle:
            return makeContentStyleToolbarItem(identifier: itemIdentifier)
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

    private func makeContentStyleToolbarItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let labels = [DemoPageContentStyle.centeredTitle.segmentLabel, DemoPageContentStyle.horizontalScroll.segmentLabel]
        let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: self, action: #selector(contentStyleDidChange))
        control.controlSize = .small
        control.selectedSegment = contentStyle.rawValue
        control.setWidth(70, forSegment: DemoPageContentStyle.centeredTitle.rawValue)
        control.setWidth(64, forSegment: DemoPageContentStyle.horizontalScroll.rawValue)
        contentStyleControl = control

        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "Content Style"
        item.paletteLabel = "Content Style"
        item.toolTip = "Content Style"
        item.view = control
        item.visibilityPriority = .high
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

    @objc private func contentStyleDidChange(_ sender: NSSegmentedControl) {
        guard let nextContentStyle = DemoPageContentStyle(rawValue: sender.selectedSegment), nextContentStyle != contentStyle else {
            return
        }

        contentStyle = nextContentStyle
        leftPane.setContentStyle(nextContentStyle)
        rightPane.setContentStyle(nextContentStyle)
        contentStyleControl?.selectedSegment = nextContentStyle.rawValue
        navigationToolbar.validateVisibleItems()
    }
}

private final class DemoNavigationHostController: NSViewController, NavigationStackControllerDelegate {
    var onNavigationStateChanged: (() -> Void)?

    private var contentStyle: DemoPageContentStyle
    private let initialPageCount: Int
    private var navigationController: NavigationStackController!

    init(contentStyle: DemoPageContentStyle = .centeredTitle, initialPageCount: Int = 1) {
        self.contentStyle = contentStyle
        self.initialPageCount = max(initialPageCount, 1)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

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

        let initialViewControllers = (1...initialPageCount).map { makePageViewController(number: $0) }
        navigationController = NavigationStackController()
        navigationController.setViewControllers(initialViewControllers, animated: false)
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
        let viewController = DemoPageViewController(page: DemoPage(number: number), contentStyle: contentStyle)
        viewController.onPush = { [weak self] in
            self?.pushPage()
        }
        return viewController
    }

    func setContentStyle(_ contentStyle: DemoPageContentStyle) {
        guard self.contentStyle != contentStyle else {
            return
        }

        self.contentStyle = contentStyle

        guard let navigationController else {
            return
        }

        let pageCount = max(navigationController.viewControllers.count, 1)
        let viewControllers = (1...pageCount).map { makePageViewController(number: $0) }
        navigationController.setViewControllers(viewControllers, animated: false)
        onNavigationStateChanged?()
    }

    func pushPage() {
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
    private let contentStyle: DemoPageContentStyle

    init(page: DemoPage, contentStyle: DemoPageContentStyle) {
        self.page = page
        self.contentStyle = contentStyle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = makeRootView()
    }

    private func makeRootView() -> NSView {
        switch contentStyle {
        case .centeredTitle:
            return makeCenteredTitleRootView()
        case .horizontalScroll:
            return makeHorizontalScrollRootView()
        }
    }

    private func makeCenteredTitleRootView() -> NSView {
        let view = DemoClickablePageView()
        view.onClick = { [weak self] in
            self?.onPush?()
        }
        view.wantsLayer = true
        view.layer?.backgroundColor = page.backgroundColor.cgColor
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

        return view
    }

    private func makeHorizontalScrollRootView() -> NSView {
        let scrollView = DemoHorizontalScrollView()
        scrollView.pageBackgroundColor = page.backgroundColor
        scrollView.drawsBackground = true
        scrollView.backgroundColor = page.backgroundColor
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = makeHorizontalScrollDocumentView()
        return scrollView
    }

    private func makeHorizontalScrollDocumentView() -> NSView {
        let contentTop: CGFloat = 112
        let documentView = DemoHorizontalScrollDocumentView(frame: NSRect(x: 0, y: 0, width: 1680, height: 520))
        documentView.pageBackgroundColor = page.backgroundColor
        documentView.onClick = { [weak self] in
            self?.onPush?()
        }
        documentView.wantsLayer = true
        documentView.layer?.backgroundColor = page.backgroundColor.cgColor

        let titleLabel = makeLabel(text: page.title, font: NSFont.systemFont(ofSize: 28, weight: .bold), alpha: 1.0)
        titleLabel.alignment = .left
        titleLabel.frame = NSRect(x: 28, y: contentTop, width: 320, height: 34)

        let addressLabel = makeLabel(text: page.address, font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), alpha: 0.72)
        addressLabel.alignment = .left
        addressLabel.frame = NSRect(x: 28, y: contentTop + 38, width: 360, height: 18)

        documentView.addSubview(titleLabel)
        documentView.addSubview(addressLabel)

        for index in 0..<12 {
            documentView.addSubview(makeScrollTile(index: index))
        }

        return documentView
    }

    private func makeScrollTile(index: Int) -> NSView {
        let tileWidth: CGFloat = 120
        let tileSpacing: CGFloat = 16
        let x = 24 + CGFloat(index) * (tileWidth + tileSpacing)
        let tile = NSView(frame: NSRect(x: x, y: 204, width: tileWidth, height: 184))
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 10
        tile.layer?.backgroundColor = scrollTileColor(index: index).cgColor

        let label = NSTextField(labelWithString: "Item \(index + 1)")
        label.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        tile.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: tile.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: tile.trailingAnchor, constant: -8),
        ])

        return tile
    }

    private func scrollTileColor(index: Int) -> NSColor {
        let palette: [NSColor] = [
            NSColor(calibratedRed: 0.10, green: 0.34, blue: 0.45, alpha: 1.0),
            NSColor(calibratedRed: 0.55, green: 0.20, blue: 0.28, alpha: 1.0),
            NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.24, alpha: 1.0),
            NSColor(calibratedRed: 0.40, green: 0.28, blue: 0.58, alpha: 1.0),
        ]

        return palette[(index + page.number) % palette.count]
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

private final class DemoHorizontalScrollView: NSScrollView {
    private let minimumDocumentWidth: CGFloat = 1680
    var pageBackgroundColor: NSColor = .clear {
        didSet {
            updateBackground()
        }
    }

    override var isOpaque: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackground()
    }

    override func layout() {
        super.layout()

        guard let documentView else {
            return
        }

        var documentFrame = documentView.frame
        documentFrame.size.width = max(minimumDocumentWidth, contentView.bounds.width + 1)
        documentFrame.size.height = max(contentView.bounds.height, 1)

        if documentView.frame.size != documentFrame.size {
            documentView.frame = documentFrame
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        pageBackgroundColor.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }

    private func updateBackground() {
        drawsBackground = true
        backgroundColor = pageBackgroundColor
        wantsLayer = true
        layer?.backgroundColor = pageBackgroundColor.cgColor
        contentView.drawsBackground = true
        contentView.backgroundColor = pageBackgroundColor
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = pageBackgroundColor.cgColor
        needsDisplay = true
        contentView.needsDisplay = true
    }
}

private final class DemoHorizontalScrollDocumentView: NSView {
    var onClick: (() -> Void)?
    var pageBackgroundColor: NSColor = .clear {
        didSet {
            layer?.backgroundColor = pageBackgroundColor.cgColor
            needsDisplay = true
        }
    }
    private var mouseDownLocation: NSPoint?

    override var isFlipped: Bool {
        true
    }

    override var isOpaque: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        pageBackgroundColor.setFill()
        dirtyRect.fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard super.hitTest(point) != nil else {
            return nil
        }

        return self
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocation = nil
        }

        guard let mouseDownLocation else {
            super.mouseUp(with: event)
            return
        }

        let mouseUpLocation = convert(event.locationInWindow, from: nil)
        let distance = hypot(mouseUpLocation.x - mouseDownLocation.x, mouseUpLocation.y - mouseDownLocation.y)
        if distance <= 3 {
            onClick?()
            return
        }

        super.mouseUp(with: event)
    }
}

#Preview("Split Navigation") {
    ContentView(contentStyle: .centeredTitle)
}

#Preview("Split Navigation Horizontal Scroll") {
    ContentView(contentStyle: .horizontalScroll)
}
