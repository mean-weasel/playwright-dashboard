import SwiftUI

struct ExpandedNoCDPState: View {
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "antenna.radiowaves.left.and.right.slash")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Text("No CDP port available")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Text("This session doesn't have browser debugging enabled.")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
  }
}

struct ExpandedConnectionFailedState: View {
  let cdpPort: Int

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle")
        .font(.largeTitle)
        .foregroundStyle(.orange)
      Text("Unable to connect to browser")
        .font(.subheadline)
      Text("CDP port \(cdpPort) is not responding.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

struct ExpandedLoadingSnapshotState: View {
  var body: some View {
    VStack(spacing: 12) {
      ProgressView()
        .controlSize(.large)
      Text("Loading browser snapshot...")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }
}
