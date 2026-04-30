import AppKit
import SwiftData
import SwiftUI

@MainActor private var smokeDashboardWindow: NSWindow?
@MainActor private var smokeSettingsWindow: NSWindow?

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

    let smokeArguments = SmokeLaunchArguments(arguments: CommandLine.arguments)
    let creation =
      smokeArguments.usesInMemoryStore
      ? ModelContainerFactory.makeInMemory()
      : ModelContainerFactory.makeWithDiagnostics()
    let container = creation.container
    let state: AppState
    if let daemonDirectory = smokeArguments.daemonDirectory {
      state = AppState(
        daemonDirectory: daemonDirectory,
        shouldStartScreenshots: !smokeArguments.disablesScreenshots)
    } else {
      state = AppState()
    }
    state.setPersistenceDegraded(creation.usedFallback)
    state.startSync(modelContext: container.mainContext)
    UserDefaults.standard.set(
      smokeArguments.forcesSnapshotFallback,
      forKey: DashboardSettings.forceExpandedSnapshotFallbackKey
    )
    if let sessionId = smokeArguments.selectedSessionId {
      state.selectedSessionId = sessionId
    }

    self.modelContainer = container
    self._appState = State(initialValue: state)

    if smokeArguments.opensDashboard {
      Self.openSmokeDashboardWindow(
        appState: state,
        modelContainer: container,
        initialFilter: smokeArguments.dashboardFilter)
    }
    if smokeArguments.opensSettings {
      Self.openSmokeSettingsWindow(appState: state)
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

  @MainActor
  private static func openSmokeDashboardWindow(
    appState: AppState,
    modelContainer: ModelContainer,
    initialFilter: SidebarFilter?
  ) {
    DispatchQueue.main.async {
      NSApplication.shared.setActivationPolicy(.regular)
      NSApplication.shared.activate(ignoringOtherApps: true)
      appState.isDashboardOpen = true

      let rootView = DashboardWindow(initialFilter: initialFilter)
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

  @MainActor
  private static func openSmokeSettingsWindow(appState: AppState) {
    DispatchQueue.main.async {
      NSApplication.shared.setActivationPolicy(.regular)
      NSApplication.shared.activate(ignoringOtherApps: true)

      let rootView = SettingsView()
        .environment(appState)

      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 430, height: 520),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      window.title = "Settings"
      window.center()
      window.contentView = NSHostingView(rootView: rootView)
      window.makeKeyAndOrderFront(nil)
      smokeSettingsWindow = window
    }
  }
}
