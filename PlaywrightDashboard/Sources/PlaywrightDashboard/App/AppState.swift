import SwiftUI

@Observable
final class AppState {
    var sessions: [String] = [] // Placeholder — Task 2 replaces with [SessionRecord]
    var isPopoverOpen: Bool = false
    var selectedSessionId: String?
}
