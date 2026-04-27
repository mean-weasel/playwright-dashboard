import SwiftUI

// Task 6 implements this
struct DashboardWindow: View {
    var body: some View {
        NavigationSplitView {
            Sidebar()
        } detail: {
            SessionGrid()
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}
