import SwiftUI

struct DashboardWindow: View {
  @Environment(AppState.self) private var appState
  @Environment(\.openSettings) private var openSettings
  @State private var selectedFilter: SidebarFilter?
  @State private var searchText = ""
  @AppStorage(DashboardSettings.safeModeKey) private var safeMode = true
  @AppStorage(DashboardSettings.safeModeOnboardingDismissedKey) private
    var safeModeOnboardingDismissed = false

  init(initialFilter: SidebarFilter? = .allOpen) {
    _selectedFilter = State(initialValue: initialFilter)
  }

  var body: some View {
    ZStack(alignment: .topTrailing) {
      NavigationSplitView {
        Sidebar(selectedFilter: $selectedFilter)
          .environment(appState)
          .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
      } detail: {
        if let session = selectedSession {
          ExpandedSessionView(session: session)
            .environment(appState)
        } else {
          SessionGrid(filter: selectedFilter, searchText: $searchText)
            .environment(appState)
        }
      }

      if safeMode && selectedSession == nil {
        VStack(alignment: .trailing, spacing: 10) {
          SafeModeBadge()

          if !safeModeOnboardingDismissed {
            SafeModeOnboardingBanner(
              onOpenSettings: { openSettings() },
              onDismiss: { safeModeOnboardingDismissed = true }
            )
          }
        }
        .padding(.top, 10)
        .padding(.trailing, 14)
      }
    }
    .frame(minWidth: 900, minHeight: 550)
  }

  private var selectedSession: SessionRecord? {
    guard let selectedId = appState.selectedSessionId else { return nil }
    return appState.sessions.first(where: { $0.sessionId == selectedId })
  }
}
