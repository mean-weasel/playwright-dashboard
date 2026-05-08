import SwiftUI

extension SessionInfoBar {
  func commitRename() {
    appState.rename(session, to: editText)
    isEditing = false
  }

  var navigationControl: some View {
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

  func syncNavigationText() {
    navigationText = session.lastURL.flatMap { $0.isEmpty ? nil : $0 } ?? ""
  }

  var recordingHelp: String {
    if isRecording {
      return "Stop recording. \(recordingFrameCount) frames captured."
    }
    if canRecord {
      return "Record live screencast frames."
    }
    return "Recording is available while live screencast is active."
  }

  var interactionHelp: String {
    if safeModeEnabled {
      return "Safe mode keeps browser frames view-only."
    }
    if interactionEnabled {
      return "Click, scroll, and keyboard input are forwarded to the browser surface."
    }
    return "Browser frames are view-only; input is not forwarded."
  }

  func beginNavigation() {
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
