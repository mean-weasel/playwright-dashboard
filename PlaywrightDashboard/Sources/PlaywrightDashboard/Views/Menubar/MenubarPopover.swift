import SwiftUI

private struct ContentHeightKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

struct MenubarPopover: View {
  @Environment(AppState.self) private var appState
  @Environment(\.openWindow) private var openWindow
  @State private var listContentHeight: CGFloat = 0
  @AppStorage("popoverGroupByApp") private var groupByApp = true

  private let maxListHeight: CGFloat = 480

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Summary strip
      summaryStrip
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)

      Divider()

      // Session list or empty state
      if nonClosedSessions.isEmpty {
        emptyState
      } else {
        sessionList
      }

      Divider()

      // Footer
      footer
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    .frame(width: 300)
  }

  // MARK: - Subviews

  private var summaryStrip: some View {
    VStack(spacing: 8) {
      HStack(spacing: 12) {
        HStack(spacing: 4) {
          Circle()
            .fill(.green)
            .frame(width: 7, height: 7)
          Text("\(activeSessions.count) active")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        HStack(spacing: 4) {
          Circle()
            .fill(.orange)
            .frame(width: 7, height: 7)
          Text("\(idleSessions.count) idle")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if !staleSessions.isEmpty {
          Button {
            appState.closeAndTerminateStaleSessions()
          } label: {
            Text("Clean up")
              .font(.caption)
          }
          .buttonStyle(.plain)
          .foregroundStyle(.blue)
        }
      }

      Picker(
        "View",
        selection: Binding(
          get: { groupByApp },
          set: { newValue in
            groupByApp = newValue
            listContentHeight = 0
          }
        )
      ) {
        Label("By App", systemImage: "folder").tag(true)
        Label("All", systemImage: "list.bullet").tag(false)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
    }
  }

  private var emptyState: some View {
    VStack(spacing: 6) {
      Text("No active sessions")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
  }

  private var sessionList: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        if groupByApp {
          ForEach(groupedWorkspaces, id: \.key) { workspace, sessions in
            workspaceSection(name: workspace, sessions: sessions)
          }
        } else {
          ForEach(
            nonClosedSessions.sorted(by: {
              $0.displayName < $1.displayName
            }), id: \.sessionId
          ) { session in
            sessionRow(session)
          }
        }
      }
      .background(
        GeometryReader { geo in
          Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
        })
    }
    .frame(height: min(listContentHeight, maxListHeight))
    .onPreferenceChange(ContentHeightKey.self) { listContentHeight = $0 }
  }

  private func workspaceSection(name: String, sessions: [SessionRecord]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(name)
        .font(.caption2)
        .fontWeight(.medium)
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)

      ForEach(sessions, id: \.sessionId) { session in
        sessionRow(session)
      }
    }
  }

  private func sessionRow(_ session: SessionRecord) -> some View {
    Button {
      appState.selectedSessionId = session.sessionId
      openWindow(id: "dashboard")
    } label: {
      HStack(spacing: 10) {
        Group {
          if let nsImage = session.screenshotImage {
            Image(nsImage: nsImage)
              .resizable()
              .scaledToFill()
          } else {
            RoundedRectangle(cornerRadius: 4)
              .fill(Color.gray.opacity(0.15))
              .overlay {
                Image(systemName: "globe")
                  .font(.caption2)
                  .foregroundStyle(.quaternary)
              }
          }
        }
        .frame(width: 32, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 4))

        VStack(alignment: .leading, spacing: 2) {
          Text(session.displayName)
            .font(.caption)
            .lineLimit(1)
            .foregroundStyle(.primary)
          if let url = session.lastURL {
            Text(url)
              .font(.caption2)
              .lineLimit(1)
              .foregroundStyle(.tertiary)
          }
        }

        Spacer()

        StatusBadge(status: session.status)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(session.displayName)
    .accessibilityIdentifier("menubar-session-row-\(session.sessionId)")
  }

  private var footer: some View {
    HStack(spacing: 8) {
      Button {
        openWindow(id: "dashboard")
      } label: {
        Text("Open Dashboard")
          .font(.subheadline)
          .fontWeight(.medium)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 4)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)

      Button {
        NSApplication.shared.terminate(nil)
      } label: {
        Image(systemName: "power")
          .font(.subheadline)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .accessibilityLabel("Quit")
    }
  }

  // MARK: - Data Helpers

  private var nonClosedSessions: [SessionRecord] {
    appState.sessions.filter { $0.status != .closed }
  }

  private var activeSessions: [SessionRecord] {
    appState.sessions.filter { $0.status == .active }
  }

  private var idleSessions: [SessionRecord] {
    appState.sessions.filter { $0.status == .idle }
  }

  private var staleSessions: [SessionRecord] {
    appState.sessions.filter { $0.status == .stale }
  }

  private var groupedWorkspaces: [(key: String, value: [SessionRecord])] {
    let grouped = Dictionary(grouping: nonClosedSessions) { $0.projectName }
    return grouped.sorted { $0.key < $1.key }
  }
}
