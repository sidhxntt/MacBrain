import AppKit

enum OverlayWindowPolicy {
    static let level: NSWindow.Level = .statusBar
    static let sidebarStyleMask: NSWindow.StyleMask = [
        .borderless,
        .nonactivatingPanel,
        .resizable,
        .fullSizeContentView
    ]

    static let sidebarCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .stationary
    ]

    static let activationBarCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .stationary
    ]
}
