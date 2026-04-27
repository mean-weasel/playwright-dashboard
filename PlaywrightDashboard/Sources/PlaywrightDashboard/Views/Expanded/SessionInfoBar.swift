import SwiftUI

struct SessionInfoBar: View {
  let session: SessionRecord
  let onBack: () -> Void
  @Binding var showMetadata: Bool

  var body: some View {
    HStack(spacing: 12) {
      Button(action: onBack) {
        Label("Back", systemImage: "chevron.left")
          .labelStyle(.titleAndIcon)
      }
      .buttonStyle(.plain)

      StatusBadge(status: session.status)

      Text(session.customName ?? session.autoLabel)
        .font(.headline)
        .lineLimit(1)

      Spacer()

      if let url = session.lastURL, !url.isEmpty {
        Text(url)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: 300)
      }

      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          showMetadata.toggle()
        }
      } label: {
        Image(systemName: showMetadata ? "sidebar.trailing" : "info.circle")
          .font(.body)
      }
      .buttonStyle(.plain)
      .help(showMetadata ? "Hide metadata" : "Show metadata")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.bar)
  }
}
