import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  @Environment(AppState.self) private var appState
  @State private var showClearClosedConfirmation = false
  @State private var copiedFeedbackSummary = false
  @State private var copiedDiagnostics = false
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
      Section("App") {
        LabeledContent("Version") {
          Text(appVersionText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }

        Button {
          appState.openLatestRelease()
        } label: {
          Label("Open Latest Release", systemImage: "arrow.up.circle")
        }
      }

      Section("Beta Feedback") {
        HStack {
          Button {
            copyFeedbackSummary()
          } label: {
            Label(
              copiedFeedbackSummary ? "Copied" : "Copy Feedback Summary",
              systemImage: copiedFeedbackSummary ? "checkmark" : "doc.on.clipboard"
            )
          }

          Button {
            exportDiagnostics()
          } label: {
            Label("Export Diagnostics", systemImage: "square.and.arrow.down")
          }
        }
      }

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
          VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
              Image(systemName: "externaldrive.badge.exclamationmark")
                .foregroundStyle(.orange)
              Text("Temporary only")
            }
            if let reason = appState.persistenceDegradedReason {
              Text(reason)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
            }
          }
        }
      }

      Section("Diagnostics") {
        LabeledContent("Daemon path") {
          Text(appState.daemonDirectoryPath)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.trailing)
            .textSelection(.enabled)
        }

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Button {
              copyDiagnostics()
            } label: {
              Label(
                copiedDiagnostics ? "Copied" : "Copy App Diagnostics",
                systemImage: copiedDiagnostics ? "checkmark" : "doc.on.doc"
              )
            }
          }

          HStack {
            Button {
              appState.revealApplicationSupportDirectory()
            } label: {
              Label("Reveal Storage", systemImage: "folder")
            }
          }
        }

        if let exportURL = appState.lastDiagnosticsExportURL {
          Label {
            Text(exportURL.lastPathComponent)
              .font(.caption)
          } icon: {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
          }
        }

        if let exportError = appState.lastDiagnosticsExportError {
          Label {
            Text(exportError)
              .font(.caption)
              .lineLimit(2)
          } icon: {
            Image(systemName: "externaldrive.badge.exclamationmark")
              .foregroundStyle(.red)
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

  private func copyFeedbackSummary() {
    appState.copyFeedbackSummary()
    copiedFeedbackSummary = true
    Task {
      try? await Task.sleep(for: .seconds(2))
      await MainActor.run {
        copiedFeedbackSummary = false
      }
    }
  }

  private func copyDiagnostics() {
    appState.copyAppDiagnostics()
    copiedDiagnostics = true
    Task {
      try? await Task.sleep(for: .seconds(2))
      await MainActor.run {
        copiedDiagnostics = false
      }
    }
  }

  private func exportDiagnostics() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [UTType.plainText]
    panel.nameFieldStringValue = "playwright-dashboard-diagnostics.txt"
    panel.canCreateDirectories = true
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor in
        appState.exportAppDiagnostics(to: url)
      }
    }
  }

  private var appVersionText: String {
    let version =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
      ?? "unknown"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    return "\(version) (\(build))"
  }
}
