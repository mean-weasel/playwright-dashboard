import CoreServices
import Testing

@testable import PlaywrightDashboard

@Suite("FSEventsStream")
struct FSEventsStreamTests {

  @Test("events pairs paths with flags")
  func eventsPairsPathsWithFlags() {
    let flags: [FSEventStreamEventFlags] = [
      FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
      FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved),
    ]

    let events = flags.withUnsafeBufferPointer { buffer in
      FSEventsStream.events(
        paths: ["/tmp/a.session", "/tmp/b.session"],
        eventFlags: buffer.baseAddress!,
        count: 2
      )
    }

    #expect(events?.map(\.path) == ["/tmp/a.session", "/tmp/b.session"])
    #expect(events?[0].flags.contains(.created) == true)
    #expect(events?[1].flags.contains(.removed) == true)
  }

  @Test("events rejects batches with fewer paths than event count")
  func eventsRejectsShortPathBatch() {
    let flags: [FSEventStreamEventFlags] = [
      FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
      FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved),
    ]

    let events = flags.withUnsafeBufferPointer { buffer in
      FSEventsStream.events(
        paths: ["/tmp/a.session"],
        eventFlags: buffer.baseAddress!,
        count: 2
      )
    }

    #expect(events == nil)
  }

  @Test("events rejects negative counts")
  func eventsRejectsNegativeCount() {
    let flags: [FSEventStreamEventFlags] = [
      FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)
    ]

    let events = flags.withUnsafeBufferPointer { buffer in
      FSEventsStream.events(
        paths: ["/tmp/a.session"],
        eventFlags: buffer.baseAddress!,
        count: -1
      )
    }

    #expect(events == nil)
  }
}
