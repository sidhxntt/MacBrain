import AppKit

struct SidebarGeometry: Equatable, Sendable {
    static let minimumWidth: CGFloat = 320
    static let maximumWidth: CGFloat = 720
    static let minimumHeight: CGFloat = 320
    static let edgeInset: CGFloat = 8

    static func frame(
        in visibleFrame: CGRect,
        requestedWidth: CGFloat,
        edge: SidebarEdge
    ) -> CGRect {
        let availableWidth = max(0, visibleFrame.width - edgeInset * 2)
        let width = min(max(requestedWidth, minimumWidth), min(maximumWidth, availableWidth))
        let height = max(0, visibleFrame.height - edgeInset * 2)
        let originX: CGFloat

        switch edge {
        case .left:
            originX = visibleFrame.minX + edgeInset
        case .right:
            originX = visibleFrame.maxX - width - edgeInset
        }

        return CGRect(
            x: originX,
            y: visibleFrame.minY + edgeInset,
            width: width,
            height: height
        )
    }
}
