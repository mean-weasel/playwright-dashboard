import SwiftUI

struct SessionMetadataPanel: View {
  let session: SessionRecord

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        metadataSection("Browser") {
          metadataRow("URL", value: session.lastURL ?? "—", copyable: true)
          metadataRow("Title", value: session.lastTitle ?? "—", copyable: false)
          metadataRow("CDP Port", value: "\(session.cdpPort)", copyable: true)
        }

        metadataSection("Workspace") {
          metadataRow(
            "Project", value: AutoLabeler.titleCase(workspaceName: session.projectName),
            copyable: false)
          metadataRow(
            "Worktree", value: AutoLabeler.titleCase(workspaceName: session.workspaceName),
            copyable: false)
          metadataRow("Directory", value: session.workspaceDir, copyable: true)
        }

        metadataSection("Session") {
          metadataRow("ID", value: session.sessionId, copyable: true)
          metadataRow("Status", value: session.status.rawValue.capitalized, copyable: false)
          metadataRow("Created", value: relativeDate(session.createdAt), copyable: false)
          metadataRow("Last Activity", value: relativeDate(session.lastActivityAt), copyable: false)
        }
      }
      .padding(16)
    }
    .frame(width: 220)
    .background(.background.secondary)
  }

  // MARK: - Helpers

  private func metadataSection(
    _ title: String, @ViewBuilder content: () -> some View
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
      content()
    }
  }

  private func metadataRow(_ label: String, value: String, copyable: Bool) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.caption2)
        .foregroundStyle(.tertiary)
      HStack(spacing: 4) {
        Group {
          if copyable {
            Text(value)
              .font(.caption)
              .lineLimit(2)
              .textSelection(.enabled)
          } else {
            Text(value)
              .font(.caption)
              .lineLimit(2)
              .textSelection(.disabled)
          }
        }
        if copyable {
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
          } label: {
            Image(systemName: "doc.on.doc")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .help("Copy to clipboard")
        }
      }
    }
  }

  private static let relativeDateFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
  }()

  private func relativeDate(_ date: Date) -> String {
    Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
  }
}
