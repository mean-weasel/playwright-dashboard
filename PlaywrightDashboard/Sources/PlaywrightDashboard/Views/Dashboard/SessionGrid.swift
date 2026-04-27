import SwiftUI

// Task 6 implements this
struct SessionGrid: View {
    var body: some View {
        ContentUnavailableView(
            "No Sessions",
            systemImage: "rectangle.grid.2x2",
            description: Text("Active Playwright sessions will appear here.")
        )
    }
}
