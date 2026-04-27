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

    private var activeSessionCount: Int {
        appState.sessions.filter { $0.status != .closed }.count
    }

    var body: some Scene {
        MenuBarExtra {
            MenubarPopover()
                .environment(appState)
        } label: {
            Label(
                "Playwright Dashboard",
                systemImage: activeSessionCount > 0
                    ? "\(activeSessionCount).circle"
                    : "display"
            )
        }
        .menuBarExtraStyle(.window)
        .modelContainer(for: SessionRecord.self)

        Window("Playwright Dashboard", id: "dashboard") {
            DashboardWindow()
                .environment(appState)
        }
        .modelContainer(for: SessionRecord.self)
    }
}
