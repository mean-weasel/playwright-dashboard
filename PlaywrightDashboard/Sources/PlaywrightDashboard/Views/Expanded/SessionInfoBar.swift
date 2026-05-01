import SwiftUI

struct SessionInfoBar: View {
  @Environment(AppState.self) private var appState
  let session: SessionRecord
  let onBack: () -> Void
  let onNavigate: (String) async throws -> String
  @Binding var showMetadata: Bool
  @Binding var interactionEnabled: Bool
  let connectionSummary: ExpandedConnectionSummary
  @State private var isEditing = false
  @State private var editText = ""
  @State private var navigationText = ""
  @State private var isNavigating = false
  @State private var navigationError: String?
  @FocusState private var isFieldFocused: Bool
  @FocusState private var isURLFieldFocused: Bool

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

      navigationControl

      connectionSummary

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

      if let error = navigationError {
        warningLabel("Navigate failed", message: error) {
          navigationError = nil
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

      Picker(
        "Interaction mode",
        selection: Binding(
          get: { interactionEnabled },
          set: { interactionEnabled = $0 }
        )
      ) {
        Label("View", systemImage: "eye").tag(false)
        Label("Control", systemImage: "cursorarrow.click.2").tag(true)
      }
      .pickerStyle(.segmented)
      .controlSize(.small)
      .frame(width: 150)
      .disabled(session.cdpPort <= 0 || session.lastScreenshot == nil)
      .accessibilityLabel("Browser interaction mode")
      .accessibilityIdentifier("expanded-interaction-mode")
      .help(
        interactionEnabled
          ? "Click, scroll, and keyboard input are forwarded to the browser surface."
          : "Browser frames are view-only; input is not forwarded.")

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
    .onAppear {
      syncNavigationText()
    }
    .onChange(of: session.lastURL) {
      guard !isURLFieldFocused, !isNavigating else { return }
      syncNavigationText()
    }
  }

  private func commitRename() {
    appState.rename(session, to: editText)
    isEditing = false
  }

  private var navigationControl: some View {
    HStack(spacing: 6) {
      TextField("URL", text: $navigationText)
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
        .font(.caption)
        .frame(width: 280)
        .focused($isURLFieldFocused)
        .onSubmit {
          beginNavigation()
        }
        .disabled(session.cdpPort <= 0 || isNavigating)
        .accessibilityLabel("Navigate URL")
        .accessibilityIdentifier("expanded-navigate-url-field")

      Button {
        beginNavigation()
      } label: {
        if isNavigating {
          ProgressView()
            .controlSize(.small)
            .frame(width: 14, height: 14)
        } else {
          Image(systemName: "arrow.right.circle")
            .font(.body)
        }
      }
      .buttonStyle(.plain)
      .disabled(
        session.cdpPort <= 0 || isNavigating
          || navigationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      )
      .accessibilityLabel("Navigate")
      .accessibilityIdentifier("expanded-navigate-url-button")
      .help("Navigate current page")
    }
  }

  private func syncNavigationText() {
    navigationText = session.lastURL.flatMap { $0.isEmpty ? nil : $0 } ?? ""
  }

  private func beginNavigation() {
    guard !isNavigating else { return }
    let requestedURL = navigationText
    isNavigating = true
    navigationError = nil
    Task {
      do {
        let normalizedURL = try await onNavigate(requestedURL)
        navigationText = normalizedURL
        isURLFieldFocused = false
      } catch {
        navigationError = error.localizedDescription
      }
      isNavigating = false
    }
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
