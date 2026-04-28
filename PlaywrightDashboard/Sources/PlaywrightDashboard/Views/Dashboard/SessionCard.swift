import SwiftUI

struct SessionCard: View {
  let session: SessionRecord
  var onSelect: (() -> Void)?

  @State private var isHovered = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Screenshot area with 16:10 aspect ratio
      ZStack(alignment: .topTrailing) {
        screenshotArea
        statusOverlay
      }
      .aspectRatio(16.0 / 10.0, contentMode: .fit)
      .clipShape(RoundedRectangle(cornerRadius: 8))

      // Bottom info section
      VStack(alignment: .leading, spacing: 4) {
        Text(session.displayName)
          .font(.headline)
          .lineLimit(1)

        HStack(spacing: 4) {
          Image(systemName: "folder")
            .font(.caption2)
            .foregroundStyle(.secondary)
          Text(AutoLabeler.titleCase(workspaceName: session.workspaceName))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        if let url = session.lastURL, !url.isEmpty, url != "about:blank" {
          Text(url)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
      }
      .padding(10)
    }
    .background(.background)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(
          isHovered ? Color.accentColor.opacity(0.6) : Color.clear,
          lineWidth: 2
        )
    )
    .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
    .onHover { hovering in
      isHovered = hovering
    }
    .onTapGesture {
      onSelect?()
    }
  }

  @ViewBuilder
  private var screenshotArea: some View {
    if let nsImage = session.screenshotImage {
      Image(nsImage: nsImage)
        .resizable()
        .scaledToFill()
    } else {
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.gray.opacity(0.15))
        .overlay {
          Image(systemName: "globe")
            .font(.largeTitle)
            .foregroundStyle(.quaternary)
        }
    }
  }

  @ViewBuilder
  private var statusOverlay: some View {
    switch session.status {
    case .active:
      statusBadgeOverlay(text: "Active", color: .green, icon: nil)
    case .idle:
      statusBadgeOverlay(text: "Idle", color: .orange, icon: nil)
    case .stale:
      staleBadgeOverlay
    case .closed:
      statusBadgeOverlay(text: "Closed", color: .secondary, icon: nil)
    }
  }

  private func statusBadgeOverlay(text: String, color: Color, icon: String?) -> some View {
    HStack(spacing: 3) {
      if let icon {
        Image(systemName: icon)
          .font(.caption2)
      }
      Circle()
        .fill(color)
        .frame(width: 6, height: 6)
      Text(text)
        .font(.caption2)
        .fontWeight(.medium)
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .background(.ultraThinMaterial, in: Capsule())
    .padding(6)
  }

  private var staleBadgeOverlay: some View {
    HStack(spacing: 3) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.caption2)
        .foregroundStyle(.yellow)
      Text(staleReason)
        .font(.caption2)
        .fontWeight(.medium)
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .background(.ultraThinMaterial, in: Capsule())
    .padding(6)
  }

  private var staleReason: String {
    if session.lastURL == nil || session.lastURL == "about:blank" {
      return "No navigation"
    }
    return "Idle 2m+"
  }
}
