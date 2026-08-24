import AppKit

@MainActor
protocol ScreenProviding {
    func targetScreen(for panel: NSPanel?) -> NSScreen?
}

@MainActor
struct SystemScreenProvider: ScreenProviding {
    func targetScreen(for panel: NSPanel?) -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? panel?.screen
            ?? NSScreen.main
    }
}
