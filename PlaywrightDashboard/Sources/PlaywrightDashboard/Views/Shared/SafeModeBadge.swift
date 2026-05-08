import SwiftUI

struct SafeModeBadge: View {
  var compact = false

  var body: some View {
    Label(compact ? "Safe" : "Safe Mode", systemImage: "lock.shield")
      .font(.caption)
      .fontWeight(.medium)
      .labelStyle(.titleAndIcon)
      .foregroundStyle(.green)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.green.opacity(0.12), in: Capsule())
      .accessibilityIdentifier("safe-mode-badge")
      .help("Safe read-only mode is enabled.")
  }
}
