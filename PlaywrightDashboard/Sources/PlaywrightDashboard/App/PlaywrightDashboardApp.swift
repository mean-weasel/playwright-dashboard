import AppKit
import ApplicationServices
import SwiftData
import SwiftUI

@MainActor private var smokeDashboardWindow: NSWindow?
@MainActor private var smokeSettingsWindow: NSWindow?

@main
struct PlaywrightDashboardApp: App {
  @State private var appState: AppState
  private let modelContainer: ModelContainer
  private let smokeArguments: SmokeLaunchArguments

  private var activeSessionCount: Int {
    appState.sessions.filter { $0.status != .closed }.count
  }

  @MainActor
  init() {
    UserDefaults.standard.register(defaults: DashboardSettings.registrationDefaults())

    let smokeArguments = SmokeLaunchArguments(arguments: CommandLine.arguments)
    let creation: ModelContainerCreation =
      if smokeArguments.usesInMemoryStore {
        ModelContainerFactory.makeInMemory()
      } else if let storeDirectory = smokeArguments.persistentStorePath {
        ModelContainerFactory.makeWithCustomStore(at: storeDirectory)
      } else {
        ModelContainerFactory.makeWithDiagnostics()
      }
    let container = creation.container
    let state: AppState
    if let daemonDirectory = smokeArguments.daemonDirectory {
      state = AppState(
        daemonDirectory: daemonDirectory,
        shouldStartScreenshots: !smokeArguments.disablesScreenshots)
    } else {
      state = AppState()
    }
    state.setPersistenceDegraded(
      creation.usedFallback,
      reason: creation.persistenceErrorDescription
    )
    state.startSync(modelContext: container.mainContext)
    if let snapshotFallbackOverride = smokeArguments.snapshotFallbackOverride {
      UserDefaults.standard.set(
        snapshotFallbackOverride,
        forKey: DashboardSettings.forceExpandedSnapshotFallbackKey
      )
    }
    if let safeModeOverride = smokeArguments.safeModeOverride {
      UserDefaults.standard.set(
        safeModeOverride,
        forKey: DashboardSettings.safeModeKey
      )
    }
    if let sessionId = smokeArguments.selectedSessionId {
      state.selectedSessionId = sessionId
    }
    if smokeArguments.opensDashboard || smokeArguments.opensSettings {
      NSApplication.shared.setActivationPolicy(.regular)
    }

    self.modelContainer = container
    self.smokeArguments = smokeArguments
    self._appState = State(initialValue: state)
    SmokeReadinessReporter.configure(
      directory: smokeArguments.readinessDirectory,
      navigationURL: smokeArguments.navigationURL
    )

    if smokeArguments.opensDashboard {
      Self.openSmokeDashboardWindow(
        appState: state,
        modelContainer: container,
        initialFilter: smokeArguments.dashboardFilter)
    }
    if smokeArguments.opensSettings {
      Self.openSmokeSettingsWindow(appState: state)
    }
    SmokeRecordingExportRunner.startIfNeeded(arguments: smokeArguments, appState: state)
    SmokeStartupActions.start(arguments: smokeArguments, appState: state)
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
          : "theatermasks"
      )
    }
    .menuBarExtraStyle(.window)
    .modelContainer(modelContainer)

    Window("Playwright Dashboard", id: "dashboard") {
      dashboardWindow
    }
    .modelContainer(modelContainer)
    .defaultSize(width: 1100, height: 700)

    WindowGroup("Detached Session", for: String.self) { $sessionId in
      DetachedSessionWindow(sessionId: sessionId)
        .environment(appState)
    }
    .modelContainer(modelContainer)
    .defaultSize(width: 980, height: 680)

    Settings {
      SettingsView()
        .environment(appState)
    }
  }

}

private struct DetachedSessionWindow: View {
  @Environment(AppState.self) private var appState
  @Environment(\.dismiss) private var dismiss
  let sessionId: String?

  var body: some View {
    if let session {
      ExpandedSessionView(session: session, onBack: { dismiss() })
        .environment(appState)
        .frame(minWidth: 760, minHeight: 480)
    } else {
      ContentUnavailableView(
        "Session unavailable",
        systemImage: "xmark.circle",
        description: Text("The selected Playwright session is no longer available.")
      )
      .frame(minWidth: 520, minHeight: 320)
    }
  }

  private var session: SessionRecord? {
    guard let sessionId else { return nil }
    return appState.sessions.first { $0.sessionId == sessionId }
  }
}

extension PlaywrightDashboardApp {
  private var dashboardWindow: some View {
    DashboardWindow(initialFilter: smokeArguments.dashboardFilter)
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
    scheduleSmokeWindowOpen {
      makeSmokeProcessForeground()
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
      window.setAccessibilityElement(true)
      window.setAccessibilityRole(.window)
      window.setAccessibilitySubrole(.standardWindow)
      window.setAccessibilityTitle("Playwright Dashboard")
      window.center()
      window.collectionBehavior = [.moveToActiveSpace]
      window.isReleasedWhenClosed = false
      window.contentViewController = NSHostingController(rootView: rootView)
      window.makeKeyAndOrderFront(nil)
      window.orderFrontRegardless()
      NSApplication.shared.activate(ignoringOtherApps: true)
      smokeDashboardWindow = window
    }
  }

  @MainActor
  private static func openSmokeSettingsWindow(appState: AppState) {
    scheduleSmokeWindowOpen {
      makeSmokeProcessForeground()

      let rootView = SettingsView()
        .environment(appState)

      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 430, height: 520),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      window.title = "Settings"
      window.setAccessibilityElement(true)
      window.setAccessibilityRole(.window)
      window.setAccessibilitySubrole(.standardWindow)
      window.setAccessibilityTitle("Settings")
      window.center()
      window.collectionBehavior = [.moveToActiveSpace]
      window.isReleasedWhenClosed = false
      window.contentViewController = NSHostingController(rootView: rootView)
      window.makeKeyAndOrderFront(nil)
      window.orderFrontRegardless()
      NSApplication.shared.activate(ignoringOtherApps: true)
      smokeSettingsWindow = window
    }
  }

  @MainActor
  private static func scheduleSmokeWindowOpen(_ action: @escaping @MainActor () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      Task { @MainActor in
        action()
      }
    }
  }

  @MainActor
  private static func makeSmokeProcessForeground() {
    var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
    TransformProcessType(
      &psn,
      ProcessApplicationTransformState(kProcessTransformToForegroundApplication))
    NSApplication.shared.setActivationPolicy(.regular)
    if NSApplication.shared.mainMenu == nil {
      NSApplication.shared.mainMenu = NSMenu(title: "Main Menu")
    }
    NSApplication.shared.unhide(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
}
