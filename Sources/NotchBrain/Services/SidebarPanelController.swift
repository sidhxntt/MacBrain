import AppKit
import SwiftUI
import os

@MainActor
final class SidebarPanelController: NSObject, NSWindowDelegate {
    private let logger = Logger(subsystem: "com.notchbrain.app", category: "sidebar")
    private let screenProvider: any ScreenProviding
    nonisolated(unsafe) private var displayObserver: NSObjectProtocol?

    private(set) var panel: SidebarPanel?
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
    }

    func show() {
        let panel = makePanelIfNeeded()
        reposition(panel, preservingCurrentWidth: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        logger.info("Sidebar shown")
    }

    func hide(notify: Bool = true) {
        panel?.orderOut(nil)
        logger.info("Sidebar hidden")
        if notify { onHide?() }
    }

    func dismiss() {
        panel?.close()
        logger.info("Sidebar dismissed")
    }

    func focus() {
        show()
        panel?.orderFrontRegardless()
        panel?.makeKey()
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
        panel.contentView = NSHostingView(rootView: makeSidebarView())
        self.panel = panel

        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.displayParametersChanged() }
        }

        return panel
    }

    private func makeSidebarView() -> SidebarView {
        SidebarView(
            presentation: presentation,
            onTogglePresentation: { [weak self] in self?.togglePresentation() },
            onClose: { [weak self] in self?.hide() }
        )
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
        panel.setFrame(frame, display: true, animate: panel.isVisible)
        panel.contentView = NSHostingView(rootView: makeSidebarView())
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
        onHide?()
        logger.info("Sidebar window closed")
    }
}
