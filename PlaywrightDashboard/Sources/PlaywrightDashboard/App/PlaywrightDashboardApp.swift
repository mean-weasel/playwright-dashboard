import AppKit
import SwiftData
import SwiftUI

@main
struct PlaywrightDashboardApp: App {
  @State private var appState = AppState()

  private var activeSessionCount: Int {
    appState.sessions.filter { $0.status != .closed }.count
  }

  init() {
    UserDefaults.standard.register(defaults: [
      "staleThresholdSeconds": 120
    ])
  }

  var body: some Scene {
    MenuBarExtra {
      MenubarPopover()
        .environment(appState)
    } label: {
      Label(
        "Playwright Dashboard",
        systemImage: activeSessionCount > 0
          ? "\(min(activeSessionCount, 50)).circle"
          : "display"
      )
    }
    .menuBarExtraStyle(.window)
    .modelContainer(for: SessionRecord.self)

    Window("Playwright Dashboard", id: "dashboard") {
      DashboardWindow()
        .environment(appState)
        .onAppear {
          appState.isDashboardOpen = true
          NSApplication.shared.setActivationPolicy(.regular)
          NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    .modelContainer(for: SessionRecord.self)
    .defaultSize(width: 1100, height: 700)

    Settings {
      SettingsView()
    }
  }
}
