import SwiftUI

struct ExpandedWarningLabel: View {
  let title: String
  let message: String
  let onDismiss: () -> Void

  init(_ title: String, message: String, onDismiss: @escaping () -> Void) {
    self.title = title
    self.message = message
    self.onDismiss = onDismiss
  }

  var body: some View {
    HStack(spacing: 4) {
      Label(title, systemImage: "exclamationmark.triangle.fill")
        .font(.caption)
        .foregroundStyle(.orange)
        .help(message)
      Button(action: onDismiss) {
        Image(systemName: "xmark.circle.fill")
          .font(.caption)
      }
      .buttonStyle(.plain)
      .help("Dismiss")
    }
  }
}
