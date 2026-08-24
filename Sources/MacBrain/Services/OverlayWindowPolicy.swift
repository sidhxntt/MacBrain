import AppKit

enum OverlayWindowPolicy {
    static let applicationActivationPolicy: NSApplication.ActivationPolicy = .regular
    static let level: NSWindow.Level = .statusBar
    static let clickShieldLevel = NSWindow.Level(rawValue: level.rawValue - 1)
    static let sidebarStyleMask: NSWindow.StyleMask = [
        .borderless,
        .resizable,
        .fullSizeContentView
    ]

    static let clickShieldStyleMask: NSWindow.StyleMask = [
        .borderless,
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
