import SwiftUI

// Task 5 implements this
struct MenubarPopover: View {
    var body: some View {
        VStack {
            Text("Playwright Dashboard")
                .font(.headline)
            Text("No active sessions")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 280)
    }
}
