import SwiftUI
import SwiftData

@Observable
final class AppState {
    var sessions: [SessionRecord] = []
    var isPopoverOpen: Bool = false
    var selectedSessionId: String?
}
