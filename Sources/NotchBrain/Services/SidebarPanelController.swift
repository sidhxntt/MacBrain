import AppKit
import SwiftUI
import os

@MainActor
final class SidebarPanelController: NSObject, NSWindowDelegate {
    private let transitionDuration: TimeInterval = 0.24
    private let logger = Logger(subsystem: "com.notchbrain.app", category: "sidebar")
    private let screenProvider: any ScreenProviding
    private let chatStore = ChatStore()
    nonisolated(unsafe) private var displayObserver: NSObjectProtocol?
    nonisolated(unsafe) private var appDeactivationObserver: NSObjectProtocol?

    private(set) var panel: SidebarPanel?
    private var clickShield: ClickShieldPanel?
    private(set) var presentation: SidebarPresentation = .compact
    var onHide: (() -> Void)?

    init(screenProvider: any ScreenProviding = SystemScreenProvider()) {
        self.screenProvider = screenProvider
        super.init()
    }

    deinit {
        if let displayObserver {
            NotificationCenter.default.removeObserver(displayObserver)
        }
        if let appDeactivationObserver {
            NotificationCenter.default.removeObserver(appDeactivationObserver)
        }
    }

    func show() {
        let panel = makePanelIfNeeded()
        guard let screen = screenProvider.targetScreen(for: panel) else {
            logger.error("Cannot show sidebar because no display is available")
            return
        }

        if panel.isVisible {
            showClickShield(on: screen)
            bringToFrontAndFocus(panel)
            return
        }

        let currentWidth = panel.frame.width > 0 ? panel.frame.width : presentation.preferredWidth
        let targetFrame = SidebarGeometry.frame(
            in: screen.visibleFrame,
            requestedWidth: currentWidth,
            edge: .right
        )
        panel.contentView = SidebarHostingView(rootView: makeSidebarView())
        panel.setFrame(targetFrame.offsetBy(dx: targetFrame.width, dy: 0), display: false)
        showClickShield(on: screen)
        bringToFrontAndFocus(panel)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = transitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame, display: true)
        }
        logger.info("Sidebar shown")
    }

    func hide(notify: Bool = true) {
        guard let panel, panel.isVisible else {
            hideClickShield()
            if notify { onHide?() }
            return
        }

        guard notify else {
            panel.orderOut(nil)
            hideClickShield()
            logger.info("Sidebar hidden")
            return
        }

        let exitFrame = panel.frame.offsetBy(dx: panel.frame.width, dy: 0)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = transitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(exitFrame, display: true)
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor [weak self, weak panel] in
                panel?.orderOut(nil)
                self?.hideClickShield()
                self?.onHide?()
            }
        }
        logger.info("Sidebar hidden")
    }

    func dismiss() {
        panel?.close()
        hideClickShield()
        logger.info("Sidebar dismissed")
    }

    func focus() {
        show()
        if let panel {
            bringToFrontAndFocus(panel)
        }
        logger.info("Sidebar focused")
    }

    func togglePresentation() {
        presentation = presentation == .compact ? .expanded : .compact
        guard let panel else { return }
        reposition(panel, requestedWidth: presentation.preferredWidth)
        logger.info("Sidebar presentation changed")
    }

    private func makePanelIfNeeded() -> SidebarPanel {
        if let panel { return panel }

        let panel = SidebarPanel(
            contentRect: .zero,
            styleMask: OverlayWindowPolicy.sidebarStyleMask,
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("com.notchbrain.sidebar")
        panel.delegate = self
        panel.level = OverlayWindowPolicy.level
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = OverlayWindowPolicy.sidebarCollectionBehavior
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hasShadow = false
        panel.minSize = NSSize(width: SidebarGeometry.minimumWidth, height: SidebarGeometry.minimumHeight)
        panel.maxSize = NSSize(width: SidebarGeometry.maximumWidth, height: 10_000)
        panel.contentView = SidebarHostingView(rootView: makeSidebarView())
        self.panel = panel

        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.displayParametersChanged() }
        }

        appDeactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.hide() }
        }

        return panel
    }

    private func makeClickShieldIfNeeded() -> ClickShieldPanel {
        if let clickShield { return clickShield }

        let shield = ClickShieldPanel(
            contentRect: .zero,
            styleMask: OverlayWindowPolicy.clickShieldStyleMask,
            backing: .buffered,
            defer: false
        )
        shield.level = OverlayWindowPolicy.clickShieldLevel
        shield.isFloatingPanel = true
        shield.isOpaque = false
        shield.backgroundColor = .clear
        shield.hidesOnDeactivate = false
        shield.collectionBehavior = OverlayWindowPolicy.sidebarCollectionBehavior
        shield.hasShadow = false
        let shieldView = ClickShieldView { [weak self] in
            self?.hide()
        }
        shieldView.wantsLayer = true
        shieldView.layer?.backgroundColor = NSColor.clear.cgColor
        shield.contentView = shieldView
        clickShield = shield
        return shield
    }

    private func showClickShield(on screen: NSScreen) {
        let shield = makeClickShieldIfNeeded()
        shield.setFrame(screen.frame, display: false)
        shield.orderFrontRegardless()
    }

    private func hideClickShield() {
        clickShield?.orderOut(nil)
    }

    private func makeSidebarView() -> SidebarView {
        SidebarView(
            presentation: presentation,
            chatStore: chatStore,
            onTogglePresentation: { [weak self] in self?.togglePresentation() }
        )
    }

    private func bringToFrontAndFocus(_ panel: SidebarPanel) {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func reposition(
        _ panel: SidebarPanel,
        requestedWidth: CGFloat? = nil,
        preservingCurrentWidth: Bool = false
    ) {
        guard let screen = screenProvider.targetScreen(for: panel) else {
            logger.error("Cannot position sidebar because no display is available")
            return
        }

        let currentWidth = panel.frame.width > 0 ? panel.frame.width : presentation.preferredWidth
        let width = requestedWidth ?? (preservingCurrentWidth ? currentWidth : presentation.preferredWidth)
        let frame = SidebarGeometry.frame(in: screen.visibleFrame, requestedWidth: width, edge: .right)
        showClickShield(on: screen)
        panel.setFrame(frame, display: true, animate: panel.isVisible)
        panel.contentView = SidebarHostingView(rootView: makeSidebarView())
        logger.debug("Sidebar positioned on display")
    }

    private func displayParametersChanged() {
        guard let panel else { return }
        reposition(panel, preservingCurrentWidth: true)
        logger.info("Display parameters changed; sidebar repositioned")
    }

    func windowDidResize(_ notification: Notification) {
        logger.debug("Sidebar resized")
    }

    func windowDidBecomeKey(_ notification: Notification) {
        logger.debug("Sidebar focused")
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        hideClickShield()
        onHide?()
        logger.info("Sidebar window closed")
    }
}
