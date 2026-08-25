import CoreGraphics

enum DesktopSidebarMetrics {
    static let minimumWidth: CGFloat = 280
    static let maximumWidth: CGFloat = 340

    static func idealWidth(for titles: [String]) -> CGFloat {
        let longestTitle = titles.map(\.count).max() ?? 0
        let calculatedWidth = CGFloat(longestTitle) * 6.7 + 180
        return min(max(calculatedWidth, minimumWidth), maximumWidth)
    }
}

enum DesktopSidebarPresentation {
    static let minimumWidth = DesktopSidebarMetrics.minimumWidth
    static let maximumWidth = DesktopSidebarMetrics.maximumWidth
}
