import SwiftData
import Foundation

// Task 2 implements this
@Model
final class SessionRecord {
    var id: String = ""
    var createdAt: Date = Date()

    init() {}
}
