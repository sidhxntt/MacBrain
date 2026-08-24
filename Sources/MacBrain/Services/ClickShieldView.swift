import AppKit

final class ClickShieldView: NSView {
    private let dismiss: () -> Void

    init(dismiss: @escaping () -> Void) {
        self.dismiss = dismiss
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        dismiss()
    }

    override func rightMouseDown(with event: NSEvent) {
        dismiss()
    }

    override func otherMouseDown(with event: NSEvent) {
        dismiss()
    }

    override func scrollWheel(with event: NSEvent) {
        // Scroll events outside the sidebar are intentionally absorbed by the
        // shield so they cannot reach the application underneath.
    }
}
