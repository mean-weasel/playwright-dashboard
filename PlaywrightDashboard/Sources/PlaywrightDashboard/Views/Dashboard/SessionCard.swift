import SwiftUI

// Task 6 implements this
struct SessionCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.background)
            .overlay {
                Text("Session")
            }
            .frame(width: 200, height: 150)
    }
}
