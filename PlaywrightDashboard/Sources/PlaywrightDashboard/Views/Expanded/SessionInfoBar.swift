import SwiftUI

struct SessionInfoBar: View {
  let session: SessionRecord
  let onBack: () -> Void
  @Binding var showMetadata: Bool
  @State private var isEditing = false
  @State private var editText = ""

  var body: some View {
    HStack(spacing: 12) {
      Button(action: onBack) {
        Label("Back", systemImage: "chevron.left")
          .labelStyle(.titleAndIcon)
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.escape, modifiers: [])
      .help("Go back (Escape)")

      StatusBadge(status: session.status)

      if isEditing {
        TextField(
          "Session name", text: $editText,
          onCommit: {
            session.customName = editText.isEmpty ? nil : editText
            isEditing = false
          }
        )
        .font(.headline)
        .textFieldStyle(.plain)
        .frame(maxWidth: 200)
        .onExitCommand {
          isEditing = false
        }
      } else {
        Text(session.displayName)
          .font(.headline)
          .lineLimit(1)
          .onTapGesture {
            editText = session.displayName
            isEditing = true
          }
          .help("Click to rename")
      }

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
