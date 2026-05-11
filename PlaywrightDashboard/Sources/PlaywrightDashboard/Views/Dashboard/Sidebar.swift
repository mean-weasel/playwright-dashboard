import SwiftUI

enum SidebarFilter: Hashable {
  case allOpen
  case idleStale
  case closed
  case workspace(String)
}

struct Sidebar: View {
  @Environment(AppState.self) private var appState
  @Binding var selectedFilter: SidebarFilter?
  @State private var showCleanupConfirmation = false
  @AppStorage(DashboardSettings.safeModeKey) private var safeMode = true

  var body: some View {
    List(selection: $selectedFilter) {
      if appState.isPersistenceDegraded {
        Section("Storage") {
          Label {
            Text("Changes won't be saved")
              .font(.caption)
              .foregroundStyle(.secondary)
          } icon: {
            Image(systemName: "externaldrive.badge.exclamationmark")
              .foregroundStyle(.orange)
          }
        }
        .accessibilityIdentifier("session-file-errors-section")
      }

      if let saveError = appState.lastPersistenceSaveError {
        Section("Save Error") {
          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
              Image(systemName: "externaldrive.badge.xmark")
                .foregroundStyle(.red)
              Text("Changes were not saved")
                .font(.caption)
              Spacer()
              Button {
                appState.dismissPersistenceSaveError()
              } label: {
                Image(systemName: "xmark")
                  .font(.caption2)
              }
              .buttonStyle(.plain)
              .help("Dismiss")
            }
            Text(saveError)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
          .padding(.vertical, 2)
        }
      }

      Section("Status") {
        if safeMode {
          SafeModeBadge(compact: true)
            .accessibilityIdentifier("sidebar-safe-mode-badge")
        }

        sidebarRow(
          filter: .allOpen,
          title: "All Open",
          icon: "circle.fill",
          iconColor: .green,
          count: activeCount
        )
        sidebarRow(
          filter: .idleStale,
          title: "Idle / Stale",
          icon: "circle.fill",
          iconColor: .orange,
          count: idleStaleCount
        )
        sidebarRow(
          filter: .closed,
          title: "Closed",
          icon: "xmark.circle.fill",
          iconColor: .secondary,
          count: closedCount
        )
      }

      Divider()

      if !appState.sessionTerminationErrors.isEmpty {
        Section("Close Errors") {
          ForEach(terminationErrors, id: \.sessionId) { item in
            VStack(alignment: .leading, spacing: 3) {
              HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundStyle(.orange)
                Text(item.sessionId)
                  .font(.caption)
                  .lineLimit(1)
                Spacer()
                Button {
                  appState.dismissTerminationError(sessionId: item.sessionId)
                } label: {
                  Image(systemName: "xmark")
                    .font(.caption2)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
              }
              Text(item.message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
            .padding(.vertical, 2)
          }

          Button {
            appState.dismissAllTerminationErrors()
          } label: {
            Label("Dismiss All", systemImage: "xmark.circle")
          }
          .buttonStyle(.plain)
        }
      }

      if !appState.sessionFileErrors.isEmpty {
        Section("Session File Errors") {
          ForEach(sessionFileErrors, id: \.filename) { item in
            VStack(alignment: .leading, spacing: 3) {
              HStack(spacing: 6) {
                Image(systemName: "doc.badge.exclamationmark")
                  .foregroundStyle(.orange)
                Text(item.filename)
                  .font(.caption)
                  .lineLimit(1)
                Spacer()
                Button {
                  appState.dismissSessionFileError(filename: item.filename)
                } label: {
                  Image(systemName: "xmark")
                    .font(.caption2)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
              }
              Text(item.message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
            .padding(.vertical, 2)
          }

          Button {
            appState.dismissAllSessionFileErrors()
          } label: {
            Label("Dismiss All", systemImage: "xmark.circle")
          }
          .buttonStyle(.plain)
        }
      }

      Section("Workspaces") {
        ForEach(workspaces, id: \.name) { workspace in
          sidebarRow(
            filter: .workspace(workspace.name),
            title: AutoLabeler.titleCase(workspaceName: workspace.name),
            icon: "character.square.fill",
            iconColor: .blue,
            count: workspace.count
          )
        }
      }

      if staleCount > 0 {
        Section {
          Button {
            showCleanupConfirmation = true
          } label: {
            Label(
              safeMode ? "Cleanup Blocked by Safe Mode" : "Clean Up \(staleCount) Stale",
              systemImage: safeMode ? "lock.shield" : "trash"
            )
            .foregroundStyle(.orange)
          }
          .buttonStyle(.plain)
          .disabled(safeMode)
          .help(safeMode ? "Safe mode disables stale-session cleanup." : "Close stale sessions.")
          .confirmationDialog(
            "Close \(staleCount) stale sessions?",
            isPresented: $showCleanupConfirmation,
            titleVisibility: .visible
          ) {
            Button("Close All Stale", role: .destructive) {
              appState.closeAndTerminateStaleSessions()
            }
          } message: {
            Text("Closed sessions can be found in the Closed filter.")
          }
        }
      }
    }
    .listStyle(.sidebar)
    .navigationTitle("Sessions")
  }

  private func sidebarRow(
    filter: SidebarFilter,
    title: String,
    icon: String,
    iconColor: Color,
    count: Int
  ) -> some View {
    Label {
      HStack {
        Text(title)
        Spacer()
        Text("\(count)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    } icon: {
      Image(systemName: icon)
        .foregroundStyle(iconColor)
        .font(.caption)
    }
    .tag(filter)
  }

  private var activeCount: Int {
    appState.sessions.filter { $0.status != .closed }.count
  }

  private var idleStaleCount: Int {
    appState.sessions.filter { $0.status == .idle || $0.status == .stale }.count
  }

  private var closedCount: Int {
    appState.sessions.filter { $0.status == .closed }.count
  }

  private var staleCount: Int {
    appState.sessions.filter { $0.status == .stale }.count
  }

  private var terminationErrors: [(sessionId: String, message: String)] {
    appState.sessionTerminationErrors
      .map { (sessionId: $0.key, message: $0.value) }
      .sorted { $0.sessionId.localizedCaseInsensitiveCompare($1.sessionId) == .orderedAscending }
  }

  private var sessionFileErrors: [(filename: String, message: String)] {
    appState.sessionFileErrors
      .map { (filename: $0.key, message: $0.value) }
      .sorted { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending }
  }

  private var workspaces: [(name: String, count: Int)] {
    let grouped = Dictionary(grouping: appState.sessions.filter { $0.status != .closed }) {
      $0.projectName
    }
    return grouped.map { (name: $0.key, count: $0.value.count) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }
}
