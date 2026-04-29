import AppKit
import SwiftData
import SwiftUI

@main
struct PlaywrightDashboardApp: App {
  @State private var appState: AppState
  private let modelContainer: ModelContainer

  private var activeSessionCount: Int {
    appState.sessions.filter { $0.status != .closed }.count
  }

  @MainActor
  init() {
    UserDefaults.standard.register(defaults: [
      "staleThresholdSeconds": 120
    ])

    let container = ModelContainerFactory.make()
    let state = AppState()
    state.startSync(modelContext: container.mainContext)

    self.modelContainer = container
    self._appState = State(initialValue: state)
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
    .modelContainer(modelContainer)

    Window("Playwright Dashboard", id: "dashboard") {
      DashboardWindow()
        .environment(appState)
        .onAppear {
          appState.isDashboardOpen = true
          NSApplication.shared.setActivationPolicy(.regular)
          NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    .modelContainer(modelContainer)
    .defaultSize(width: 1100, height: 700)

    Settings {
      SettingsView()
    }
  }

}
