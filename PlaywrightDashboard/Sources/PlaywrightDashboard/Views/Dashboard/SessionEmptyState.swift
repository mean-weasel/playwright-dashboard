import AppKit
import SwiftUI

struct SessionEmptyState: View {
  @Environment(AppState.self) private var appState
  @Environment(\.openSettings) private var openSettings

  let filter: SidebarFilter?
  let searchText: String

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: iconName)
        .font(.system(size: 40, weight: .regular))
        .foregroundStyle(.secondary)

      VStack(spacing: 6) {
        Text(title)
          .font(.title3)
          .fontWeight(.semibold)
          .accessibilityIdentifier("session-empty-state-title")
        Text(message)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 460)
      }

      if showsSetupActions {
        VStack(spacing: 12) {
          setupCommand

          HStack(spacing: 10) {
            Button {
              openSettings()
            } label: {
              Label("Check Settings", systemImage: "gearshape")
            }

            Button {
              appState.refreshPlaywrightCLIStatus()
            } label: {
              Label("Recheck CLI", systemImage: "arrow.clockwise")
            }

            Button {
              copySetupCommand()
            } label: {
              Label("Copy Start Command", systemImage: "terminal")
            }

            Button {
              appState.copyAppDiagnostics()
            } label: {
              Label("Copy Diagnostics", systemImage: "doc.on.doc")
            }
          }
          .controlSize(.regular)
        }
      }

      if showsCLIStatus {
        VStack(spacing: 6) {
          cliStatus
          daemonPathStatus
          compatibilityStatus
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(32)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(title)
    .accessibilityValue(message)
    .accessibilityIdentifier("session-empty-state")
  }

  private var title: String {
    if hasSearchText {
      return "No Matching Sessions"
    }

    switch filter {
    case .closed:
      return "No Closed Sessions"
    case .idleStale:
      return "No Idle or Stale Sessions"
    case .workspace:
      return "No Sessions in This Workspace"
    case .allOpen, nil:
      return "No Active Sessions"
    }
  }

  private var message: String {
    if hasSearchText {
      return "Try a different session name, workspace, URL, or session ID."
    }

    switch filter {
    case .closed:
      return "Closed sessions will appear here until your retention setting removes them."
    case .idleStale:
      return "Sessions that are blank, inactive, or past the stale threshold will appear here."
    case .workspace:
      return "This workspace has no open Playwright sessions right now."
    case .allOpen, nil:
      return
        "Start a Playwright browser session with CDP enabled. The app observes session files without disrupting active browsers."
    }
  }

  private var iconName: String {
    if hasSearchText {
      return "magnifyingglass"
    }

    switch filter {
    case .closed:
      return "clock.arrow.circlepath"
    case .idleStale:
      return "pause.circle"
    case .workspace:
      return "folder"
    case .allOpen, nil:
      return "display"
    }
  }

  private var hasSearchText: Bool {
    !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var showsSetupActions: Bool {
    !hasSearchText && (filter == .allOpen || filter == nil)
  }

  private var showsCLIStatus: Bool {
    showsSetupActions && appState.playwrightCLIStatus != .unknown
  }

  private var cliStatus: some View {
    Label {
      Text(appState.playwrightCLIStatus.displayText)
        .font(.caption)
    } icon: {
      Image(
        systemName: appState.playwrightCLIStatus.isAvailable
          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
      )
      .foregroundStyle(appState.playwrightCLIStatus.isAvailable ? .green : .orange)
    }
    .foregroundStyle(.secondary)
    .padding(.top, 2)
  }

  private var setupCommand: some View {
    Text(appState.setupCommandText)
      .font(.system(.caption, design: .monospaced))
      .foregroundStyle(.secondary)
      .textSelection(.enabled)
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
      .accessibilityIdentifier("session-empty-state-setup-command")
  }

  private var daemonPathStatus: some View {
    Label {
      Text("Watching \(appState.daemonDirectoryPath)")
        .font(.caption)
        .lineLimit(2)
        .textSelection(.enabled)
    } icon: {
      Image(systemName: "folder")
    }
    .foregroundStyle(.secondary)
  }

  private var compatibilityStatus: some View {
    Label {
      Text("Sessions without a CDP port appear as non-interactive observer sessions.")
        .font(.caption)
    } icon: {
      Image(systemName: "info.circle")
    }
    .foregroundStyle(.secondary)
  }

  private func copySetupCommand() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(appState.setupCommandText, forType: .string)
  }
}
