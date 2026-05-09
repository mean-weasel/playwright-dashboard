import Foundation

extension ExpandedSessionView {
  var canRecord: Bool {
    frameMode == .liveScreencast && !isSnapshotFallback && !isFinishingRecording
  }

  func toggleRecording() {
    if isRecording {
      stopRecording()
    } else {
      startRecording()
    }
  }

  private func startRecording() {
    guard canRecord else {
      recordingError = "Recording is available while live screencast is active."
      return
    }

    let writer = ExpandedRecordingWriter(snapshot: recordingSnapshot)
    recordingWriter = writer
    recordingFrameCount = 0
    recordingError = nil
    lastRecordingURL = nil
    lastRecordingExportURL = nil
    recordingExportError = nil

    Task {
      do {
        _ = try await writer.start()
        isRecording = true
      } catch {
        recordingWriter = nil
        isRecording = false
        recordingError = error.localizedDescription
      }
    }
  }

  func stopRecording() {
    guard let writer = recordingWriter else { return }
    isFinishingRecording = true
    Task {
      do {
        let url = try await writer.finish(
          finalURL: currentFrameResult?.url,
          finalTitle: currentFrameResult?.title
        )
        lastRecordingURL = url
        lastRecordingExportURL = nil
        recordingWriter = nil
        isRecording = false
        isFinishingRecording = false
      } catch {
        recordingWriter = nil
        isRecording = false
        isFinishingRecording = false
        recordingError = error.localizedDescription
      }
    }
  }

  func exportLastRecording() {
    guard let lastRecordingURL, !isExportingRecording else { return }
    isExportingRecording = true
    recordingExportError = nil

    Task {
      do {
        let outputURL = try await ExpandedRecordingVideoExporter().exportMP4(from: lastRecordingURL)
        lastRecordingExportURL = outputURL
        isExportingRecording = false
      } catch {
        lastRecordingExportURL = nil
        isExportingRecording = false
        recordingExportError = error.localizedDescription
      }
    }
  }

  func appendRecordingFrame(_ frame: CDPClient.ScreencastFrame) {
    guard isRecording, let recordingWriter else { return }
    Task {
      do {
        let count = try await recordingWriter.append(frame: frame)
        recordingFrameCount = count
      } catch {
        if let recordingError = error as? ExpandedRecordingWriter.RecordingError,
          recordingError.isLimitReached
        {
          isFinishingRecording = true
          do {
            let url = try await recordingWriter.finish(
              finalURL: frame.url,
              finalTitle: frame.title
            )
            lastRecordingURL = url
            lastRecordingExportURL = nil
            self.recordingWriter = nil
            isRecording = false
            isFinishingRecording = false
            self.recordingError = "Recording stopped: \(recordingError.localizedDescription)"
          } catch {
            self.recordingWriter = nil
            isRecording = false
            isFinishingRecording = false
            self.recordingError = error.localizedDescription
          }
        } else {
          self.recordingWriter = nil
          isRecording = false
          isFinishingRecording = false
          recordingError = error.localizedDescription
        }
      }
    }
  }

  private var recordingSnapshot: ExpandedRecordingSessionSnapshot {
    ExpandedRecordingSessionSnapshot(
      sessionId: session.sessionId,
      displayName: session.displayName,
      targetId: session.selectedTargetId,
      initialURL: currentFrameResult?.url ?? session.lastURL,
      initialTitle: currentFrameResult?.title ?? session.lastTitle
    )
  }
}
