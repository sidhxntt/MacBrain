import AppKit
import SwiftUI

/// Lets the sidebar receive the first click anywhere in its SwiftUI surface,
/// including non-interactive empty space.
final class SidebarHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
