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

  var body: some View {
    List(selection: $selectedFilter) {
      Section("Status") {
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
            for session in appState.sessions where session.status == .stale {
              session.status = .closed
              session.closedAt = Date()
            }
          } label: {
            Label("Clean Up \(staleCount) Stale", systemImage: "trash")
              .foregroundStyle(.orange)
          }
          .buttonStyle(.plain)
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

  private var workspaces: [(name: String, count: Int)] {
    let grouped = Dictionary(grouping: appState.sessions.filter { $0.status != .closed }) {
      $0.projectName
    }
    return grouped.map { (name: $0.key, count: $0.value.count) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }
}
