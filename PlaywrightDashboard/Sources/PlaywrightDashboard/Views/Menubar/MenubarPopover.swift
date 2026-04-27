import SwiftUI

struct MenubarPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

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
                Text("Clean up")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
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
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groupedWorkspaces, id: \.key) { workspace, sessions in
                    workspaceSection(name: workspace, sessions: sessions)
                }
            }
        }
        .frame(maxHeight: 280)
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
                // Thumbnail placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.customName ?? session.autoLabel)
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
    }

    private var footer: some View {
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
        let grouped = Dictionary(grouping: nonClosedSessions) { $0.workspaceName }
        return grouped.sorted { $0.key < $1.key }
    }
}
