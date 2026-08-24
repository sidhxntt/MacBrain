import AppKit

final class ActivationBarHandleView: NSVisualEffectView {
    private let onActivate: () -> Void
    private let onDrag: (CGFloat) -> Void
    private let onDragEnd: () -> Void

    init(
        onActivate: @escaping () -> Void,
        onDrag: @escaping (CGFloat) -> Void,
        onDragEnd: @escaping () -> Void
    ) {
        self.onActivate = onActivate
        self.onDrag = onDrag
        self.onDragEnd = onDragEnd
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = ActivationBarGeometry.size.width / 2
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.30).cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.38).cgColor
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        layer?.shadowOpacity = 1
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ActivationBarGeometry.size.width, height: ActivationBarGeometry.size.height)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        let initialY = NSEvent.mouseLocation.y
        var distance: CGFloat = 0
        NSCursor.closedHand.push()
        defer { NSCursor.pop() }

        while let nextEvent = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            switch nextEvent.type {
            case .leftMouseDragged:
                distance = NSEvent.mouseLocation.y - initialY
                if ActivationBarInteraction.action(forVerticalDrag: distance) == .drag {
                    onDrag(distance)
                }
            case .leftMouseUp:
                switch ActivationBarInteraction.action(forVerticalDrag: distance) {
                case .activate:
                    onActivate()
                case .drag:
                    onDragEnd()
                }
                return
            default:
                continue
            }
        }
    }
}
