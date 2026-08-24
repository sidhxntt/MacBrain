import AppKit
import os

@MainActor
final class ActivationBarController {
    private let logger = Logger(subsystem: "com.notchbrain.app", category: "activationBar")
    private let screenProvider: any ScreenProviding
    private let onActivate: () -> Void
    nonisolated(unsafe) private var displayObserver: NSObjectProtocol?

    private(set) var panel: ActivationBarPanel?
    private var centerY: CGFloat?
    private var dragOriginY: CGFloat?

    init(
        screenProvider: any ScreenProviding = SystemScreenProvider(),
        onActivate: @escaping () -> Void
    ) {
        self.screenProvider = screenProvider
        self.onActivate = onActivate
    }

    deinit {
        if let displayObserver {
            NotificationCenter.default.removeObserver(displayObserver)
        }
    }

    func show() {
        let panel = makePanelIfNeeded()
        reposition(panel)
        panel.orderFrontRegardless()
        logger.info("Activation bar shown")
    }

    func hide() {
        panel?.orderOut(nil)
        logger.info("Activation bar hidden")
    }

    func drag(to offset: CGFloat) {
        guard let panel else { return }
        guard let screen = screenProvider.targetScreen(for: panel) else { return }

        let origin = dragOriginY ?? panel.frame.midY
        dragOriginY = origin
        centerY = origin + offset
        reposition(panel, on: screen)
    }

    func endDrag() {
        dragOriginY = nil
        logger.debug("Activation bar moved vertically")
    }

    private func makePanelIfNeeded() -> ActivationBarPanel {
        if let panel { return panel }

        let panel = ActivationBarPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("com.notchbrain.activationBar")
        panel.level = OverlayWindowPolicy.level
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = OverlayWindowPolicy.activationBarCollectionBehavior
        panel.contentView = ActivationBarHandleView(
            onActivate: onActivate,
            onDrag: { [weak self] offset in self?.drag(to: offset) },
            onDragEnd: { [weak self] in self?.endDrag() }
        )
        self.panel = panel

        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.repositionForDisplayChange() }
        }

        return panel
    }

    private func reposition(_ panel: ActivationBarPanel) {
        guard let screen = screenProvider.targetScreen(for: panel) else {
            logger.error("Cannot position activation bar because no display is available")
            return
        }

        reposition(panel, on: screen)
    }

    private func reposition(_ panel: ActivationBarPanel, on screen: NSScreen) {
        let frame = ActivationBarGeometry.frame(in: screen.visibleFrame, centerY: centerY)
        centerY = frame.midY
        panel.setFrame(frame, display: true)
    }

    private func repositionForDisplayChange() {
        guard let panel else { return }
        reposition(panel)
        logger.info("Activation bar repositioned after display change")
    }
}
