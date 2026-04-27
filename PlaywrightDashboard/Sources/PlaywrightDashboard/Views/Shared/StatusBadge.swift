import SwiftUI

// Task 5 implements this
struct StatusBadge: View {
  let status: SessionStatus

  var body: some View {
    Text(status.rawValue.capitalized)
      .font(.caption2)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(color.opacity(0.15))
      .foregroundStyle(color)
      .clipShape(Capsule())
  }

  private var color: Color {
    switch status {
    case .active: .green
    case .idle: .orange
    case .stale: .yellow
    case .closed: .secondary
    }
  }
}
