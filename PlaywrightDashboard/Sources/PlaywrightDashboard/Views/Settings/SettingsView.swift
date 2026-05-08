import SwiftUI

struct SettingsView: View {
  @Environment(AppState.self) private var appState
  @State private var showClearClosedConfirmation = false
  @AppStorage(DashboardSettings.staleThresholdSecondsKey) private var staleThresholdSeconds = 120
  @AppStorage(DashboardSettings.thumbnailRefreshSecondsKey) private var thumbnailRefreshSeconds = 5
  @AppStorage(DashboardSettings.thumbnailQualityKey) private var thumbnailQuality = 50
  @AppStorage(DashboardSettings.expandedRefreshMillisecondsKey) private
    var expandedRefreshMilliseconds = 1500
  @AppStorage(DashboardSettings.expandedQualityKey) private var expandedQuality = 60
  @AppStorage(DashboardSettings.closedSessionRetentionHoursKey) private
    var closedSessionRetentionHours = 24
  @AppStorage(DashboardSettings.safeModeKey) private var safeMode = true
  @AppStorage("launchAtLogin") private var launchAtLogin = false

  private let thresholdOptions: [(label: String, seconds: Int)] = [
    ("1 minute", 60),
    ("2 minutes", 120),
    ("5 minutes", 300),
    ("10 minutes", 600),
    ("Never", 0),
  ]

  private let thumbnailRefreshOptions: [(label: String, seconds: Int)] = [
    ("2 seconds", 2),
    ("5 seconds", 5),
    ("10 seconds", 10),
    ("30 seconds", 30),
  ]

  private let expandedRefreshOptions: [(label: String, milliseconds: Int)] = [
    ("0.5 seconds", 500),
    ("1 second", 1000),
    ("1.5 seconds", 1500),
    ("3 seconds", 3000),
  ]

  private let retentionOptions: [(label: String, hours: Int)] = [
    ("1 hour", 1),
    ("24 hours", 24),
    ("7 days", 168),
    ("30 days", 720),
    ("Never", 0),
  ]

  var body: some View {
    Form {
      Picker("Mark sessions stale after", selection: $staleThresholdSeconds) {
        ForEach(thresholdOptions, id: \.seconds) { option in
          Text(option.label).tag(option.seconds)
        }
      }

      Picker("Refresh thumbnails every", selection: $thumbnailRefreshSeconds) {
        ForEach(thumbnailRefreshOptions, id: \.seconds) { option in
          Text(option.label).tag(option.seconds)
        }
      }

      LabeledContent("Thumbnail quality") {
        Stepper(value: $thumbnailQuality, in: 10...100, step: 10) {
          Text("\(thumbnailQuality)")
            .monospacedDigit()
        }
      }

      Picker("Refresh expanded snapshot every", selection: $expandedRefreshMilliseconds) {
        ForEach(expandedRefreshOptions, id: \.milliseconds) { option in
          Text(option.label).tag(option.milliseconds)
        }
      }

      LabeledContent("Expanded quality") {
        Stepper(value: $expandedQuality, in: 10...100, step: 10) {
          Text("\(expandedQuality)")
            .monospacedDigit()
        }
      }

      Picker("Keep closed sessions", selection: $closedSessionRetentionHours) {
        ForEach(retentionOptions, id: \.hours) { option in
          Text(option.label).tag(option.hours)
        }
      }

      Toggle("Safe read-only mode", isOn: $safeMode)
        .help(
          "Disables session close actions, cleanup, CDP inspector access, navigation, and browser input forwarding."
        )

      LabeledContent("Playwright CLI") {
        HStack(spacing: 8) {
          Image(
            systemName: appState.playwrightCLIStatus.isAvailable
              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
          )
          .foregroundStyle(appState.playwrightCLIStatus.isAvailable ? .green : .orange)
          Text(appState.playwrightCLIStatus.displayText)
        }
      }

      if appState.isPersistenceDegraded {
        LabeledContent("Storage") {
          HStack(spacing: 8) {
            Image(systemName: "externaldrive.badge.exclamationmark")
              .foregroundStyle(.orange)
            Text("Temporary only")
          }
        }
      }

      Button("Clear Closed History", role: .destructive) {
        showClearClosedConfirmation = true
      }
      .disabled(appState.sessions.allSatisfy { $0.status != .closed })
      .confirmationDialog(
        "Clear closed session history?",
        isPresented: $showClearClosedConfirmation,
        titleVisibility: .visible
      ) {
        Button("Clear Closed History", role: .destructive) {
          appState.clearClosedSessions()
        }
      } message: {
        Text("This removes closed session records from the dashboard.")
      }

      Toggle("Launch at login", isOn: $launchAtLogin)
        .onChange(of: launchAtLogin) { _, enabled in
          if enabled {
            LaunchAtLoginManager.enable()
          } else {
            LaunchAtLoginManager.disable()
          }
        }
    }
    .formStyle(.grouped)
    .frame(width: 350)
    .accessibilityIdentifier("settings-view")
    .onAppear {
      // Sync toggle with actual plist state on disk
      launchAtLogin = LaunchAtLoginManager.isEnabled
      appState.refreshPlaywrightCLIStatus()
    }
  }
}
