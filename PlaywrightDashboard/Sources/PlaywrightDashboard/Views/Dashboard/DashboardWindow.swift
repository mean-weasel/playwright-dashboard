import SwiftUI

struct DashboardWindow: View {
    @Environment(AppState.self) private var appState
    @State private var selectedFilter: SidebarFilter? = .allActive
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            Sidebar(selectedFilter: $selectedFilter)
                .environment(appState)
        } detail: {
            if let selectedId = appState.selectedSessionId {
                // Expanded session view placeholder
                VStack {
                    Text("Session: \(selectedId)")
                        .font(.title2)
                    Text("Expanded view will be implemented in a future task.")
                        .foregroundStyle(.secondary)
                    Button("Back to Grid") {
                        appState.selectedSessionId = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SessionGrid(filter: selectedFilter, searchText: $searchText)
                    .environment(appState)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}
