import SwiftData
import SwiftUI

struct SessionGrid: View {
  @Environment(AppState.self) private var appState

  let filter: SidebarFilter?
  @Binding var searchText: String

  private let columns = [
    GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 10)
  ]

  @State private var renamingSession: SessionRecord?
  @State private var renameText = ""

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
          if isGroupedByWorkspace {
            groupedGrid
          } else {
            flatGrid
          }
        }
      }
    }
    .toolbar {
      ToolbarItem(placement: .automatic) {
        SearchBar(text: $searchText)
          .frame(minWidth: 200, maxWidth: 300)
      }
    }
    .alert(
      "Rename Session",
      isPresented: .init(
        get: { renamingSession != nil },
        set: { if !$0 { renamingSession = nil } }
      )
    ) {
      TextField("Session name", text: $renameText)
      Button("Save") {
        if let session = renamingSession {
          appState.rename(session, to: renameText)
        }
        renamingSession = nil
      }
      Button("Cancel", role: .cancel) {
        renamingSession = nil
      }
    } message: {
      Text("Enter a custom name for this session, or leave empty to use the auto-generated name.")
    }
  }

  // MARK: - Grid Layouts

  private var flatGrid: some View {
    LazyVGrid(columns: columns, spacing: 10) {
      ForEach(filteredSessions, id: \.sessionId) { session in
        draggableCard(for: session)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }

  private var groupedGrid: some View {
    LazyVStack(alignment: .leading, spacing: 16) {
      ForEach(groupedByWorkspace, id: \.workspace) { group in
        VStack(alignment: .leading, spacing: 8) {
          // Workspace header
          Text(AutoLabeler.titleCase(workspaceName: group.workspace))
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)

          LazyVGrid(columns: columns, spacing: 10) {
            ForEach(group.sessions, id: \.sessionId) { session in
              draggableCard(for: session)
            }
          }
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }

  private func draggableCard(for session: SessionRecord) -> some View {
    SessionCard(
      session: session,
      onSelect: {
        appState.selectedSessionId = session.sessionId
      },
      onRename: {
        renameText = session.displayName
        renamingSession = session
      }
    )
    .draggable(session.sessionId)
    .dropDestination(for: String.self) { droppedIds, _ in
      guard let sourceId = droppedIds.first else { return false }
      return appState.reorder(sourceId: sourceId, targetId: session.sessionId)
    }
  }

  // MARK: - Grouping

  /// Groups sessions by workspace for broad filters (allOpen, idleStale, nil). Closed and single-workspace filters show a flat grid.
  private var isGroupedByWorkspace: Bool {
    switch filter {
    case .allOpen, .idleStale, nil: return true
    case .closed, .workspace: return false
    }
  }

  private struct WorkspaceGroup: Identifiable {
    let workspace: String
    let sessions: [SessionRecord]
    var id: String { workspace }
  }

  private var groupedByWorkspace: [WorkspaceGroup] {
    let grouped = Dictionary(grouping: filteredSessions) { $0.projectName }
    return
      grouped
      .map {
        WorkspaceGroup(workspace: $0.key, sessions: $0.value.sorted { $0.gridOrder < $1.gridOrder })
      }
      .sorted { $0.workspace.localizedCaseInsensitiveCompare($1.workspace) == .orderedAscending }
  }

  // MARK: - Filtering

  private var filteredSessions: [SessionRecord] {
    SessionFiltering.filter(appState.sessions, by: filter, searchText: searchText)
  }
}
