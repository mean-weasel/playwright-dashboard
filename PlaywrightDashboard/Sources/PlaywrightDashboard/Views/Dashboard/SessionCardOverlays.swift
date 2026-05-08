import SwiftUI

struct SessionCardActionOverlay: View {
  @Environment(AppState.self) private var appState
  @AppStorage(DashboardSettings.safeModeKey) private var safeMode = true
  let session: SessionRecord
  let showsActions: Bool
  let onRename: () -> Void

  var body: some View {
    HStack(spacing: 5) {
      cardActionButton(
        systemImage: "pencil",
        label: "Rename session",
        identifier: "session-card-rename-\(session.sessionId)",
        action: onRename
      )

      cardActionButton(
        systemImage: "safari",
        label: "Open current URL",
        identifier: "session-card-open-url-\(session.sessionId)",
        isDisabled: !canOpenCurrentURL
      ) {
        appState.openCurrentURL(session)
      }

      cardActionButton(
        systemImage: "network",
        label: "Open CDP inspector",
        identifier: "session-card-open-cdp-\(session.sessionId)",
        isDisabled: session.cdpPort <= 0 || safeMode,
        disabledHelp: safeMode ? "Safe mode disables CDP inspector access." : nil
      ) {
        appState.openCDPInspector(session)
      }

      if session.status == .closed {
        cardActionButton(
          systemImage: "arrow.uturn.backward.circle",
          label: "Reopen session",
          identifier: "session-card-reopen-\(session.sessionId)"
        ) {
          appState.reopen(session)
        }
      } else {
        cardActionButton(
          systemImage: "xmark.circle",
          label: "Close session",
          identifier: "session-card-close-\(session.sessionId)",
          role: .destructive,
          isDisabled: session.status == .closing || safeMode,
          disabledHelp: safeMode ? "Safe mode disables session close actions." : nil
        ) {
          appState.closeAndTerminate(session)
        }
      }

      if appState.sessionTerminationErrors[session.sessionId] != nil {
        cardActionButton(
          systemImage: "arrow.clockwise.circle",
          label: "Retry close",
          identifier: "session-card-retry-close-\(session.sessionId)",
          isDisabled: safeMode,
          disabledHelp: safeMode ? "Safe mode disables session close actions." : nil
        ) {
          appState.retryTerminate(session)
        }

        cardActionButton(
          systemImage: "checkmark.circle",
          label: "Dismiss close error",
          identifier: "session-card-dismiss-close-error-\(session.sessionId)"
        ) {
          appState.dismissTerminationError(sessionId: session.sessionId)
        }
      }
    }
    .padding(6)
    .background(.ultraThinMaterial, in: Capsule())
    .padding(6)
    .opacity(showsActions ? 1 : 0)
    .allowsHitTesting(showsActions)
    .accessibilityHidden(!showsActions)
  }

  private func cardActionButton(
    systemImage: String,
    label: String,
    identifier: String,
    role: ButtonRole? = nil,
    isDisabled: Bool = false,
    disabledHelp: String? = nil,
    action: @escaping () -> Void
  ) -> some View {
    Button(role: role, action: action) {
      Image(systemName: systemImage)
        .font(.caption)
        .frame(width: 20, height: 20)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .opacity(isDisabled ? 0.45 : 1)
    .accessibilityLabel(label)
    .accessibilityIdentifier(identifier)
    .help(isDisabled ? disabledHelp ?? label : label)
  }

  private var canOpenCurrentURL: Bool {
    guard let urlString = session.lastURL,
      let url = URL(string: urlString),
      let scheme = url.scheme?.lowercased()
    else { return false }

    return ["http", "https"].contains(scheme)
  }
}

struct SessionCardThumbnailState: View {
  let session: SessionRecord

  var body: some View {
    HStack(spacing: 5) {
      Label(thumbnailStateText, systemImage: thumbnailStateIcon)
        .labelStyle(.titleAndIcon)

      Text("·")
        .foregroundStyle(.tertiary)

      Text(connectionStateText)
    }
    .font(.caption2)
    .fontWeight(.medium)
    .foregroundStyle(.secondary)
    .lineLimit(1)
    .padding(.horizontal, 7)
    .padding(.vertical, 4)
    .background(.ultraThinMaterial, in: Capsule())
    .padding(6)
    .accessibilityLabel("\(thumbnailStateText), \(connectionStateText)")
    .accessibilityIdentifier("session-card-thumbnail-state-\(session.sessionId)")
  }

  private var thumbnailStateText: String {
    guard session.lastScreenshot != nil else { return "No screenshot" }
    return
      "Updated \(Self.relativeDateFormatter.localizedString(for: session.lastActivityAt, relativeTo: Date()))"
  }

  private var thumbnailStateIcon: String {
    session.lastScreenshot == nil ? "photo" : "clock"
  }

  private var connectionStateText: String {
    session.cdpPort > 0 ? "CDP \(session.cdpPort)" : "CDP unavailable"
  }

  private static let relativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter
  }()
}
