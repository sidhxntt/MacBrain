import Foundation

struct ActivationBarGeometry: Equatable, Sendable {
    static let size = CGSize(width: 9, height: 58)
    static let edgeInset: CGFloat = 18

    static func frame(in visibleFrame: CGRect, centerY: CGFloat? = nil) -> CGRect {
        let minimumCenterY = visibleFrame.minY + edgeInset + size.height / 2
        let maximumCenterY = visibleFrame.maxY - edgeInset - size.height / 2
        let requestedCenterY = centerY ?? visibleFrame.midY
        let clampedCenterY = min(max(requestedCenterY, minimumCenterY), maximumCenterY)

        return CGRect(
            x: visibleFrame.maxX - size.width - edgeInset,
            y: clampedCenterY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
