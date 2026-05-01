import SwiftUI

struct SessionMetadataPanel: View {
  @Environment(AppState.self) private var appState
  let session: SessionRecord
  let frameMode: ExpandedFrameMode
  let targetMonitorMode: ExpandedTargetMonitorMode
  let lastCDPError: String?
  let lastTargetError: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        metadataSection("Browser") {
          if !session.pageTargets.isEmpty {
            targetPicker
          }
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
          metadataRow("Frames", value: frameMode.label, copyable: false)
          metadataRow("Targets", value: targetMonitorMode.label, copyable: false)
          metadataRow("Created", value: relativeDate(session.createdAt), copyable: false)
          metadataRow("Last Activity", value: relativeDate(session.lastActivityAt), copyable: false)
        }

        Button {
          copyDiagnostics()
        } label: {
          Label("Copy diagnostics", systemImage: "doc.on.clipboard")
            .frame(maxWidth: .infinity)
        }
        .controlSize(.small)
        .accessibilityIdentifier("expanded-copy-diagnostics")
        .help("Copy session and CDP diagnostics")
      }
      .padding(16)
    }
    .frame(width: 220)
    .background(.background.secondary)
  }

  // MARK: - Helpers

  private var targetPicker: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Target")
        .font(.caption2)
        .foregroundStyle(.tertiary)
      Picker(
        "Target",
        selection: Binding<String?>(
          get: { session.selectedPageTarget?.id },
          set: { appState.selectTarget(session, targetId: $0) }
        )
      ) {
        ForEach(session.pageTargets) { target in
          Text(targetLabel(target))
            .tag(Optional(target.id))
        }
      }
      .labelsHidden()
      .controlSize(.small)
      .frame(maxWidth: .infinity)
      .accessibilityLabel("Browser target")
      .accessibilityIdentifier("expanded-target-picker")
      .help("Select browser tab target")
    }
  }

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

  private func targetLabel(_ target: CDPPageTarget) -> String {
    let title = target.displayTitle
    if title.count <= 42 {
      return title
    }
    return "\(title.prefix(39))..."
  }

  private func copyDiagnostics() {
    let target = session.selectedPageTarget
    let diagnostics = [
      "sessionId: \(session.sessionId)",
      "status: \(session.status.rawValue)",
      "cdpPort: \(session.cdpPort)",
      "frameMode: \(frameMode.label)",
      "targetMonitorMode: \(targetMonitorMode.label)",
      "selectedTargetId: \(target?.id ?? "none")",
      "selectedTargetTitle: \(target?.displayTitle ?? "none")",
      "targetCount: \(session.pageTargets.count)",
      "url: \(session.lastURL ?? "none")",
      "lastCDPError: \(lastCDPError ?? "none")",
      "lastTargetError: \(lastTargetError ?? "none")",
    ].joined(separator: "\n")

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(diagnostics, forType: .string)
  }
}
