import SwiftUI

struct SafeModeOnboardingBanner: View {
  let onOpenSettings: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "lock.shield")
          .foregroundStyle(.green)

        VStack(alignment: .leading, spacing: 4) {
          Text("Safe read-only mode is on")
            .font(.subheadline)
            .fontWeight(.semibold)
          Text(
            "Observation stays available. Closing, cleanup, navigation, CDP inspector access, and browser input require an explicit opt-in."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }

        Button(action: onDismiss) {
          Image(systemName: "xmark.circle.fill")
            .font(.caption)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss Safe mode note")
        .accessibilityIdentifier("safe-mode-onboarding-dismiss")
        .help("Dismiss")
      }

      Button(action: onOpenSettings) {
        Label("Open Settings", systemImage: "gearshape")
      }
      .controlSize(.small)
      .accessibilityIdentifier("safe-mode-onboarding-settings")
    }
    .padding(12)
    .frame(width: 340, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(.green.opacity(0.25), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("safe-mode-onboarding-banner")
  }
}
