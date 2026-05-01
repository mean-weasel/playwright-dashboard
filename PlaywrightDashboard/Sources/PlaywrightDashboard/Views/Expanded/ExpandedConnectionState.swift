import SwiftUI

enum ExpandedFrameMode: Equatable {
  case waiting
  case liveScreencast
  case snapshotFallback
  case connectionLost

  var label: String {
    switch self {
    case .waiting: "Waiting"
    case .liveScreencast: "Live"
    case .snapshotFallback: "Snapshots"
    case .connectionLost: "Disconnected"
    }
  }

  var icon: String {
    switch self {
    case .waiting: "clock"
    case .liveScreencast: "dot.radiowaves.left.and.right"
    case .snapshotFallback: "camera.viewfinder"
    case .connectionLost: "exclamationmark.triangle.fill"
    }
  }

  var tint: Color {
    switch self {
    case .waiting: .secondary
    case .liveScreencast: .green
    case .snapshotFallback: .orange
    case .connectionLost: .red
    }
  }

  var help: String {
    switch self {
    case .waiting: "Waiting for browser frames from CDP."
    case .liveScreencast: "Receiving Page.screencastFrame events from CDP."
    case .snapshotFallback: "Screencast is unavailable; polling CDP screenshots."
    case .connectionLost: "CDP refresh is failing for this session."
    }
  }
}

enum ExpandedTargetMonitorMode: Equatable {
  case connecting
  case eventStream
  case polling
  case unavailable

  var label: String {
    switch self {
    case .connecting: "Targets"
    case .eventStream: "Targets live"
    case .polling: "Targets polling"
    case .unavailable: "Targets stale"
    }
  }

  var icon: String {
    switch self {
    case .connecting: "point.3.connected.trianglepath.dotted"
    case .eventStream: "point.3.connected.trianglepath.dotted"
    case .polling: "arrow.clockwise"
    case .unavailable: "exclamationmark.triangle.fill"
    }
  }

  var tint: Color {
    switch self {
    case .connecting: .secondary
    case .eventStream: .green
    case .polling: .orange
    case .unavailable: .red
    }
  }
}

struct ExpandedConnectionSummary: View {
  let frameMode: ExpandedFrameMode
  let targetMode: ExpandedTargetMonitorMode
  let targetCount: Int
  let selectedTarget: CDPPageTarget?
  let lastCDPError: String?
  let lastTargetError: String?

  var body: some View {
    HStack(spacing: 8) {
      statusPill(frameMode.label, icon: frameMode.icon, tint: frameMode.tint)
        .help(frameHelp)
      statusPill(targetLabel, icon: targetMode.icon, tint: targetMode.tint)
        .help(targetHelp)
      if lastCDPError != nil || lastTargetError != nil {
        statusPill("Issue", icon: "exclamationmark.circle", tint: .orange)
          .help(errorHelp)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("expanded-connection-summary")
  }

  private var targetLabel: String {
    if targetCount == 0 { return targetMode.label }
    return "\(targetMode.label) (\(targetCount))"
  }

  private var frameHelp: String {
    if let lastCDPError {
      return "\(frameMode.help)\nLast CDP error: \(lastCDPError)"
    }
    return frameMode.help
  }

  private var targetHelp: String {
    let target = selectedTarget?.displayTitle ?? "No selected target"
    if let lastTargetError {
      return "\(targetMode.label). Selected: \(target).\nLast target error: \(lastTargetError)"
    }
    return "\(targetMode.label). Selected: \(target)."
  }

  private var errorHelp: String {
    [lastCDPError, lastTargetError]
      .compactMap { $0 }
      .joined(separator: "\n")
  }

  private func statusPill(_ text: String, icon: String, tint: Color) -> some View {
    Label(text, systemImage: icon)
      .font(.caption)
      .lineLimit(1)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(tint.opacity(0.12), in: Capsule())
      .foregroundStyle(tint)
  }
}
