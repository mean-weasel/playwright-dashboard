import SwiftUI

enum SidebarFilter: Hashable {
    case allActive
    case idleStale
    case workspace(String)
}

struct Sidebar: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedFilter: SidebarFilter?

    var body: some View {
        List(selection: $selectedFilter) {
            Section("Status") {
                sidebarRow(
                    filter: .allActive,
                    title: "All Active",
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
            }

            Divider()

            Section("Workspaces") {
                ForEach(workspaces, id: \.name) { workspace in
                    sidebarRow(
                        filter: .workspace(workspace.name),
                        title: workspace.name,
                        icon: "character.square.fill",
                        iconColor: .blue,
                        count: workspace.count
                    )
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

    private var workspaces: [(name: String, count: Int)] {
        let grouped = Dictionary(grouping: appState.sessions.filter { $0.status != .closed }) {
            $0.workspaceName
        }
        return grouped.map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
