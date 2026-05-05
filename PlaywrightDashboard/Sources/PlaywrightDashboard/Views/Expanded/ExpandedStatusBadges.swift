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
  let frameMode: ExpandedFrameMode

  var body: some View {
    Label(frameMode.label, systemImage: frameMode.icon)
      .font(.caption)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.thinMaterial, in: Capsule())
      .foregroundStyle(frameMode.tint)
      .help(frameMode.help)
  }
}

struct ExpandedInteractionBadge: View {
  var body: some View {
    Label("Control mode", systemImage: "cursorarrow.click.2")
      .font(.caption)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.green.opacity(0.15))
      .foregroundStyle(.green)
      .clipShape(Capsule())
      .help("Clicks, scrolling, and keyboard input are forwarded to this browser.")
  }
}

struct ExpandedAgentActivityBadge: View {
  var body: some View {
    Label("Agent active", systemImage: "bolt.trianglebadge.exclamationmark")
      .font(.caption)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.yellow.opacity(0.18))
      .foregroundStyle(.yellow)
      .clipShape(Capsule())
      .help("The browser changed while you were in control mode.")
  }
}

struct ExpandedRecordingBadge: View {
  let frameCount: Int

  var body: some View {
    Label("Recording", systemImage: "record.circle.fill")
      .font(.caption)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.red.opacity(0.15))
      .foregroundStyle(.red)
      .clipShape(Capsule())
      .help("\(frameCount) frames captured")
  }
}
