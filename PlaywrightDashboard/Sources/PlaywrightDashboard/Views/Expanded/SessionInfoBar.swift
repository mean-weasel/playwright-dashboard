import SwiftUI

struct SessionInfoBar: View {
  @Environment(AppState.self) private var appState
  let session: SessionRecord
  let onBack: () -> Void
  @Binding var showMetadata: Bool
  @Binding var interactionEnabled: Bool
  @State private var isEditing = false
  @State private var editText = ""
  @FocusState private var isFieldFocused: Bool

  var body: some View {
    HStack(spacing: 12) {
      Button(action: onBack) {
        Label("Back", systemImage: "chevron.left")
          .labelStyle(.titleAndIcon)
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.escape, modifiers: [])
      .help("Go back (Escape)")

      StatusBadge(status: session.status)

      if isEditing {
        TextField("Session name", text: $editText)
          .font(.headline)
          .textFieldStyle(.plain)
          .frame(maxWidth: 200)
          .focused($isFieldFocused)
          .onSubmit {
            commitRename()
          }
          .onExitCommand {
            isEditing = false
          }
          .onChange(of: isFieldFocused) { _, focused in
            if !focused { commitRename() }
          }
      } else {
        Text(session.displayName)
          .font(.headline)
          .lineLimit(1)
          .onTapGesture {
            editText = session.displayName
            isEditing = true
            isFieldFocused = true
          }
          .help("Click to rename")
      }

      Spacer()

      if let url = session.lastURL, !url.isEmpty {
        Text(url)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: 300)
      }

      if let error = appState.lastScreenshotSaveError {
        warningLabel("Save failed", message: error) {
          appState.dismissScreenshotSaveError()
        }
      }

      if let error = appState.lastOpenURLError {
        warningLabel("Open failed", message: error) {
          appState.dismissOpenURLError()
        }
      }

      Button {
        _ = appState.saveScreenshot(session)
      } label: {
        Image(systemName: "square.and.arrow.down")
          .font(.body)
      }
      .buttonStyle(.plain)
      .disabled(session.lastScreenshot == nil)
      .accessibilityLabel("Save screenshot")
      .accessibilityIdentifier("expanded-save-screenshot")
      .help("Save screenshot")

      Button {
        appState.openCurrentURL(session)
      } label: {
        Image(systemName: "safari")
          .font(.body)
      }
      .buttonStyle(.plain)
      .disabled(session.lastURL == nil || session.lastURL == "about:blank")
      .accessibilityLabel("Open current URL")
      .accessibilityIdentifier("expanded-open-current-url")
      .help("Open current URL")

      Button {
        appState.openCDPInspector(session)
      } label: {
        Image(systemName: "network")
          .font(.body)
      }
      .buttonStyle(.plain)
      .disabled(session.cdpPort <= 0)
      .accessibilityLabel("Open CDP inspector")
      .accessibilityIdentifier("expanded-open-cdp-inspector")
      .help("Open CDP inspector")

      Button {
        interactionEnabled.toggle()
      } label: {
        Image(systemName: interactionEnabled ? "cursorarrow.click.2" : "cursorarrow.click")
          .font(.body)
      }
      .buttonStyle(.plain)
      .disabled(session.cdpPort <= 0 || session.lastScreenshot == nil)
      .accessibilityLabel(
        interactionEnabled ? "Disable screenshot interaction" : "Enable screenshot interaction"
      )
      .accessibilityIdentifier("expanded-interaction-toggle")
      .help(
        interactionEnabled
          ? "Disable click, scroll, and keyboard forwarding"
          : "Enable click, scroll, and keyboard forwarding from the refreshed screenshot")

      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          showMetadata.toggle()
        }
      } label: {
        Image(systemName: showMetadata ? "sidebar.trailing" : "info.circle")
          .font(.body)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(showMetadata ? "Hide metadata" : "Show metadata")
      .accessibilityIdentifier("expanded-metadata-toggle")
      .help(showMetadata ? "Hide metadata" : "Show metadata")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.bar)
  }

  private func commitRename() {
    appState.rename(session, to: editText)
    isEditing = false
  }

  private func warningLabel(
    _ title: String,
    message: String,
    onDismiss: @escaping () -> Void
  ) -> some View {
    HStack(spacing: 4) {
      Label(title, systemImage: "exclamationmark.triangle.fill")
        .font(.caption)
        .foregroundStyle(.orange)
        .help(message)
      Button(action: onDismiss) {
        Image(systemName: "xmark.circle.fill")
          .font(.caption)
      }
      .buttonStyle(.plain)
      .help("Dismiss")
    }
  }
}
