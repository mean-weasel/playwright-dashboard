import SwiftUI
import SwiftData
import AppKit

@main
struct PlaywrightDashboardApp: App {
    @State private var appState = AppState()

    init() {
        // LSUIElement equivalent — hide from Dock, keep menubar extra visible
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("Playwright Dashboard", systemImage: "display") {
            MenubarPopover()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Window("Playwright Dashboard", id: "dashboard") {
            DashboardWindow()
                .environment(appState)
        }
    }
}
