import Foundation

enum SessionFiltering {
  static func filter(
    _ sessions: [SessionRecord],
    by sidebarFilter: SidebarFilter?,
    searchText: String = ""
  ) -> [SessionRecord] {
    var result = sessions

    switch sidebarFilter {
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

    let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedQuery.isEmpty {
      let query = trimmedQuery.lowercased()
      result = result.filter { session in
        session.autoLabel.lowercased().contains(query)
          || session.sessionId.lowercased().contains(query)
          || session.projectName.lowercased().contains(query)
          || session.workspaceName.lowercased().contains(query)
          || (session.lastURL?.lowercased().contains(query) ?? false)
          || (session.customName?.lowercased().contains(query) ?? false)
      }
    }

    result.sort { $0.gridOrder < $1.gridOrder }
    return result
  }
}
