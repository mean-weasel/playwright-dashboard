import SwiftUI

struct ExpandedConnectionWarningBadge: View {
  var body: some View {
    Label("Connection lost", systemImage: "exclamationmark.triangle.fill")
      .font(.caption)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.orange.opacity(0.15))
      .foregroundStyle(.orange)
      .clipShape(Capsule())
  }
}

struct ExpandedRefreshBadge: View {
  let isScreencasting: Bool
  let isSnapshotFallback: Bool

  var body: some View {
    Label(text, systemImage: icon)
      .font(.caption)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.thinMaterial, in: Capsule())
      .foregroundStyle(isScreencasting ? .green : .secondary)
      .help(help)
  }

  private var text: String {
    if isScreencasting {
      return "Live screencast"
    }
    if isSnapshotFallback {
      return "Snapshot fallback"
    }
    return "Snapshot refresh"
  }

  private var icon: String {
    isScreencasting ? "dot.radiowaves.left.and.right" : "camera.viewfinder"
  }

  private var help: String {
    if isScreencasting {
      return "Receiving Page.screencastFrame events from CDP."
    }
    if isSnapshotFallback {
      return "Screencast is unavailable; this view is polling CDP screenshots."
    }
    return "Waiting for CDP browser frames."
  }
}

struct ExpandedInteractionBadge: View {
  var body: some View {
    Label("Screenshot interaction on", systemImage: "cursorarrow.click")
      .font(.caption)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.green.opacity(0.15))
      .foregroundStyle(.green)
      .clipShape(Capsule())
  }
}
