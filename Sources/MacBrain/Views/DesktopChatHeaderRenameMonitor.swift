import AppKit
import SwiftUI

/// Observes the native navigation-title area without replacing the desktop header.
struct DesktopChatHeaderRenameMonitor: NSViewRepresentable {
    let onRename: @MainActor @Sendable () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRename: onRename)
    }

    func makeNSView(context: Context) -> NSView {
        let view = MonitorView(frame: .zero)
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onRename = onRename
        context.coordinator.installMonitor(in: view.window)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        var onRename: @MainActor @Sendable () -> Void
        private weak var window: NSWindow?
        private var monitor: Any?

        init(onRename: @escaping @MainActor @Sendable () -> Void) {
            self.onRename = onRename
        }

        func installMonitor(in window: NSWindow?) {
            guard self.window !== window else { return }
            removeMonitor()
            self.window = window
            guard let window else { return }
            let onRename = onRename
            let headerHeight: CGFloat = 96
            let titleLeadingEdge = min(360, window.frame.width * 0.35)
            let titleMinimumY = window.frame.height - headerHeight

            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak window, onRename] event in
                guard let window, event.window === window, event.clickCount == 2 else {
                    return event
                }

                let location = event.locationInWindow
                guard location.y >= titleMinimumY, location.x >= titleLeadingEdge else {
                    return event
                }

                Task { @MainActor in
                    onRename()
                }
                return event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            window = nil
        }
    }

    final class MonitorView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.installMonitor(in: window)
        }
    }
}
