import AppKit

final class ActivationBarHandleView: NSVisualEffectView {
    private let onActivate: () -> Void
    private let onDrag: (CGFloat) -> Void
    private let onDragEnd: () -> Void
    private let hoverGlowLayer = CAShapeLayer()
    private var hoverTrackingArea: NSTrackingArea?

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

        hoverGlowLayer.fillColor = NSColor.clear.cgColor
        hoverGlowLayer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.90).cgColor
        hoverGlowLayer.lineWidth = 1.25
        hoverGlowLayer.shadowColor = NSColor.controlAccentColor.cgColor
        hoverGlowLayer.shadowRadius = 5
        hoverGlowLayer.shadowOpacity = 0
        hoverGlowLayer.opacity = 0
        layer?.addSublayer(hoverGlowLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ActivationBarGeometry.size.width, height: ActivationBarGeometry.size.height)
    }

    override func layout() {
        super.layout()
        hoverGlowLayer.frame = bounds
        let outlineRect = bounds.insetBy(dx: 1, dy: 1)
        hoverGlowLayer.path = CGPath(
            roundedRect: outlineRect,
            cornerWidth: outlineRect.width / 2,
            cornerHeight: outlineRect.width / 2,
            transform: nil
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        setHoverGlowVisible(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHoverGlowVisible(false)
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

    private func setHoverGlowVisible(_ isVisible: Bool) {
        hoverGlowLayer.removeAllAnimations()

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        hoverGlowLayer.opacity = isVisible ? 1 : 0
        hoverGlowLayer.shadowOpacity = isVisible ? 0.85 : 0
        layer?.borderColor = NSColor.white
            .withAlphaComponent(isVisible ? 0.70 : 0.30)
            .cgColor
        CATransaction.commit()

        guard isVisible else { return }

        let pulse = CABasicAnimation(keyPath: #keyPath(CALayer.shadowOpacity))
        pulse.fromValue = 0.35
        pulse.toValue = 0.95
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        hoverGlowLayer.add(pulse, forKey: "hoverGlowPulse")
    }
}
