import Foundation
import os

@MainActor
final class AppCoordinator {
    private let logger = Logger(subsystem: "com.notchbrain.app", category: "lifecycle")
    private(set) var sidebarController: SidebarPanelController?
    private(set) var activationBarController: ActivationBarController?

    func start() {
        logger.info("Application launched")
        let sidebar = SidebarPanelController()
        let activationBar = ActivationBarController { [weak self] in
            self?.openSidebar()
        }

        sidebar.onHide = { [weak activationBar] in
            activationBar?.show()
        }
        sidebarController = sidebar
        activationBarController = activationBar
        activationBar.show()
    }

    func stop() {
        activationBarController?.hide()
        sidebarController?.hide(notify: false)
        logger.info("Application stopped")
    }

    private func openSidebar() {
        activationBarController?.hide()
        sidebarController?.focus()
    }
}
