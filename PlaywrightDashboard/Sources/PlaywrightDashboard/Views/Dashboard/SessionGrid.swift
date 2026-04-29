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
          let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
          session.customName = trimmed.isEmpty ? nil : trimmed
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
      return reorder(sourceId: sourceId, targetId: session.sessionId)
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
    var result = appState.sessions

    switch filter {
    case .allOpen:
      result = result.filter { $0.status != .closed }
    case .idleStale:
      result = result.filter { $0.status == .idle || $0.status == .stale }
    case .closed:
      result = result.filter { $0.status == .closed }
    case .workspace(let name):
      result = result.filter { $0.projectName == name && $0.status != .closed }
    case nil:
      result = result.filter { $0.status != .closed }
    }

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

    result.sort { $0.gridOrder < $1.gridOrder }
    return result
  }

  private func reorder(sourceId: String, targetId: String) -> Bool {
    guard sourceId != targetId else { return false }
    guard let source = appState.sessions.first(where: { $0.sessionId == sourceId }),
      let target = appState.sessions.first(where: { $0.sessionId == targetId })
    else { return false }

    let temp = source.gridOrder
    source.gridOrder = target.gridOrder
    target.gridOrder = temp
    return true
  }
}
