import SwiftUI
import SwiftData

struct SessionGrid: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    let filter: SidebarFilter?
    @Binding var searchText: String

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 320), spacing: 16)
    ]

    var body: some View {
        Group {
            if filteredSessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "rectangle.grid.2x2",
                    description: Text("Active Playwright sessions will appear here.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredSessions, id: \.sessionId) { session in
                            SessionCard(session: session) {
                                appState.selectedSessionId = session.sessionId
                            }
                            .draggable(session.sessionId)
                        }
                    }
                    .padding()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                SearchBar(text: $searchText)
                    .frame(minWidth: 200, maxWidth: 300)
            }
        }
    }

    private var filteredSessions: [SessionRecord] {
        var result = appState.sessions

        // Apply sidebar filter
        switch filter {
        case .allActive:
            result = result.filter { $0.status != .closed }
        case .idleStale:
            result = result.filter { $0.status == .idle || $0.status == .stale }
        case .workspace(let name):
            result = result.filter { $0.workspaceName == name && $0.status != .closed }
        case nil:
            result = result.filter { $0.status != .closed }
        }

        // Apply search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { session in
                session.autoLabel.lowercased().contains(query)
                || session.sessionId.lowercased().contains(query)
                || session.workspaceName.lowercased().contains(query)
                || (session.lastURL?.lowercased().contains(query) ?? false)
                || (session.customName?.lowercased().contains(query) ?? false)
            }
        }

        // Sort by grid order
        result.sort { $0.gridOrder < $1.gridOrder }

        return result
    }
}
