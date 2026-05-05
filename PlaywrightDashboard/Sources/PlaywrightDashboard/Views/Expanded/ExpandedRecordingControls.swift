import SwiftUI

struct ExpandedRecordingControls: View {
  @Environment(AppState.self) private var appState
  let lastRecordingURL: URL
  let lastRecordingExportURL: URL?
  let isExportingRecording: Bool
  let onExportRecording: () -> Void

  var body: some View {
    Button(action: onExportRecording) {
      if isExportingRecording {
        ProgressView()
          .controlSize(.small)
          .frame(width: 14, height: 14)
      } else {
        Image(systemName: "film")
          .font(.body)
      }
    }
    .buttonStyle(.plain)
    .disabled(isExportingRecording)
    .accessibilityLabel("Export recording MP4")
    .accessibilityIdentifier("expanded-export-recording")
    .help(recordingExportHelp)

    Button {
      appState.openRecordingDirectory(lastRecordingURL)
    } label: {
      Image(systemName: lastRecordingExportURL == nil ? "folder" : "folder.badge.film")
        .font(.body)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Show recording in Finder")
    .accessibilityIdentifier("expanded-show-recording")
    .help("Show last recording in Finder")
  }

  private var recordingExportHelp: String {
    if isExportingRecording {
      return "Exporting MP4..."
    }
    if lastRecordingExportURL != nil {
      return "Re-export MP4 from the last recording."
    }
    return "Export MP4 from the last recording."
  }
}
