import SwiftUI

struct SessionInfoBar: View {
  @Environment(AppState.self) private var appState
  let session: SessionRecord
  let onBack: () -> Void
  let onDetach: (() -> Void)?
  let onNavigate: (String) async throws -> String
  let canRecord: Bool
  let isRecording: Bool
  let isFinishingRecording: Bool
  let recordingFrameCount: Int
  let recordingError: String?
  let lastRecordingURL: URL?
  let lastRecordingExportURL: URL?
  let isExportingRecording: Bool
  let recordingExportError: String?
  let onToggleRecording: () -> Void
  let onExportRecording: () -> Void
  let onDismissRecordingError: () -> Void
  let onDismissRecordingExportError: () -> Void
  @Binding var showMetadata: Bool
  @Binding var interactionEnabled: Bool
  let safeModeEnabled: Bool
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

      if safeModeEnabled {
        SafeModeBadge(compact: true)
          .accessibilityIdentifier("expanded-safe-mode-badge")
      }

      connectionSummary

      if let error = appState.lastScreenshotSaveError {
        ExpandedWarningLabel("Save failed", message: error) {
          appState.dismissScreenshotSaveError()
        }
      }

      if let error = appState.lastOpenURLError {
        ExpandedWarningLabel("Open failed", message: error) {
          appState.dismissOpenURLError()
        }
      }

      if let error = navigationError {
        ExpandedWarningLabel("Navigate failed", message: error) {
          navigationError = nil
        }
      }

      if let error = recordingError {
        ExpandedWarningLabel("Record failed", message: error) {
          onDismissRecordingError()
        }
      }

      if let error = recordingExportError {
        ExpandedWarningLabel("Export failed", message: error) {
          onDismissRecordingExportError()
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
      .disabled(session.cdpPort <= 0 || safeModeEnabled)
      .accessibilityLabel("Open CDP inspector")
      .accessibilityIdentifier("expanded-open-cdp-inspector")
      .help(safeModeEnabled ? "Safe mode disables CDP inspector access." : "Open CDP inspector")

      Button(action: onToggleRecording) {
        if isFinishingRecording {
          ProgressView()
            .controlSize(.small)
            .frame(width: 14, height: 14)
        } else {
          Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
            .font(.body)
        }
      }
      .buttonStyle(.plain)
      .disabled((!isRecording && !canRecord) || isFinishingRecording)
      .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
      .accessibilityIdentifier("expanded-recording-toggle")
      .help(recordingHelp)

      if let lastRecordingURL {
        ExpandedRecordingControls(
          lastRecordingURL: lastRecordingURL,
          lastRecordingExportURL: lastRecordingExportURL,
          isExportingRecording: isExportingRecording,
          onExportRecording: onExportRecording
        )
      }

      if let onDetach {
        Button(action: onDetach) {
          Image(systemName: "macwindow.on.rectangle")
            .font(.body)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open detached window")
        .accessibilityIdentifier("expanded-open-detached-window")
        .help("Open detached window")
      }

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
      .disabled(safeModeEnabled || session.cdpPort <= 0 || session.lastScreenshot == nil)
      .accessibilityLabel("Browser interaction mode")
      .accessibilityIdentifier("expanded-interaction-mode")
      .help(interactionHelp)

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
        .disabled(safeModeEnabled || session.cdpPort <= 0 || isNavigating)
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
        safeModeEnabled || session.cdpPort <= 0 || isNavigating
          || navigationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      )
      .accessibilityLabel("Navigate")
      .accessibilityIdentifier("expanded-navigate-url-button")
      .help(safeModeEnabled ? "Safe mode disables browser navigation." : "Navigate current page")
    }
  }

  private func syncNavigationText() {
    navigationText = session.lastURL.flatMap { $0.isEmpty ? nil : $0 } ?? ""
  }

  private var recordingHelp: String {
    if isRecording {
      return "Stop recording. \(recordingFrameCount) frames captured."
    }
    if canRecord {
      return "Record live screencast frames."
    }
    return "Recording is available while live screencast is active."
  }

  private var interactionHelp: String {
    if safeModeEnabled {
      return "Safe mode keeps browser frames view-only."
    }
    if interactionEnabled {
      return "Click, scroll, and keyboard input are forwarded to the browser surface."
    }
    return "Browser frames are view-only; input is not forwarded."
  }

  private func beginNavigation() {
    guard !safeModeEnabled, !isNavigating else { return }
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

}
