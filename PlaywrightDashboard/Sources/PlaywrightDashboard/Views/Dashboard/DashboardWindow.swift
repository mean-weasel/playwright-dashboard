import SwiftUI

struct DashboardWindow: View {
  @Environment(AppState.self) private var appState
  @State private var selectedFilter: SidebarFilter?
  @State private var searchText = ""

  init(initialFilter: SidebarFilter? = .allOpen) {
    _selectedFilter = State(initialValue: initialFilter)
  }

  var body: some View {
    NavigationSplitView {
      Sidebar(selectedFilter: $selectedFilter)
        .environment(appState)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
    } detail: {
      if let selectedId = appState.selectedSessionId,
        let session = appState.sessions.first(where: { $0.sessionId == selectedId })
      {
        ExpandedSessionView(session: session)
          .environment(appState)
      } else {
        SessionGrid(filter: selectedFilter, searchText: $searchText)
          .environment(appState)
      }
    }
    .frame(minWidth: 900, minHeight: 550)
  }
}
