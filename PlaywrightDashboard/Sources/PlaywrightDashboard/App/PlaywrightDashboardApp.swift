import AppKit
import SwiftData
import SwiftUI

@MainActor private var smokeDashboardWindow: NSWindow?

@main
struct PlaywrightDashboardApp: App {
  @State private var appState: AppState
  private let modelContainer: ModelContainer

  private var activeSessionCount: Int {
    appState.sessions.filter { $0.status != .closed }.count
  }

  @MainActor
  init() {
    UserDefaults.standard.register(defaults: DashboardSettings.registrationDefaults())

    let container = ModelContainerFactory.make()
    let state = AppState()
    state.startSync(modelContext: container.mainContext)
    let arguments = CommandLine.arguments
    if let sessionId = Self.smokeSelectedSessionId(arguments: arguments) {
      state.selectedSessionId = sessionId
    }

    self.modelContainer = container
    self._appState = State(initialValue: state)

    if arguments.contains("--smoke-open-dashboard") {
      Self.openSmokeDashboardWindow(appState: state, modelContainer: container)
    }
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
      dashboardWindow
    }
    .modelContainer(modelContainer)
    .defaultSize(width: 1100, height: 700)

    Settings {
      SettingsView()
        .environment(appState)
    }
  }

}

extension PlaywrightDashboardApp {
  private var dashboardWindow: some View {
    DashboardWindow()
      .environment(appState)
      .onAppear {
        appState.isDashboardOpen = true
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
      }
  }

  private static func smokeSelectedSessionId(arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: "--smoke-session-id"),
      arguments.indices.contains(index + 1)
    else {
      return nil
    }
    return arguments[index + 1]
  }

  @MainActor
  private static func openSmokeDashboardWindow(
    appState: AppState,
    modelContainer: ModelContainer
  ) {
    DispatchQueue.main.async {
      NSApplication.shared.setActivationPolicy(.regular)
      NSApplication.shared.activate(ignoringOtherApps: true)
      appState.isDashboardOpen = true

      let rootView = DashboardWindow()
        .environment(appState)
        .modelContainer(modelContainer)

      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
      )
      window.title = "Playwright Dashboard"
      window.center()
      window.contentView = NSHostingView(rootView: rootView)
      window.makeKeyAndOrderFront(nil)
      smokeDashboardWindow = window
    }
  }
}
