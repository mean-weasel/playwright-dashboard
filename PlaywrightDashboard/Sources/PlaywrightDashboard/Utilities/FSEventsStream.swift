import CoreServices
import Foundation

/// A reusable Swift wrapper around the FSEvents C API.
/// Watches a directory recursively and fires a callback when files change.
final class FSEventsStream: Sendable {
  /// The flags reported for each event.
  struct EventFlags: OptionSet, Sendable {
    let rawValue: UInt32

    static let created = EventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemCreated))
    static let removed = EventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemRemoved))
    static let modified = EventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemModified))
    static let renamed = EventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemRenamed))
    static let isFile = EventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemIsFile))
    static let isDir = EventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemIsDir))
  }

  /// A single file-system event.
  struct Event: Sendable {
    let path: String
    let flags: EventFlags
  }

  /// Callback type fired after debounce with the batch of events.
  typealias Handler = @Sendable ([Event]) -> Void

  private let path: String
  private let debounceInterval: TimeInterval
  private let handler: Handler
  private let queue: DispatchQueue

  // Mutable state protected by the queue
  private nonisolated(unsafe) var stream: FSEventStreamRef?
  private nonisolated(unsafe) var debounceWork: DispatchWorkItem?
  private nonisolated(unsafe) var pendingEvents: [Event] = []
  private nonisolated(unsafe) var isRunning: Bool = false

  /// Creates a new FSEvents watcher.
  /// - Parameters:
  ///   - path: The directory to watch recursively.
  ///   - debounceInterval: Seconds to wait after last event before calling handler. Defaults to 0.5.
  ///   - handler: Called with accumulated events after the debounce period.
  init(path: String, debounceInterval: TimeInterval = 0.5, handler: @escaping Handler) {
    self.path = path
    self.debounceInterval = debounceInterval
    self.handler = handler
    self.queue = DispatchQueue(label: "FSEventsStream.\(path)", qos: .utility)
  }

  deinit {
    // Stop must be called before deallocation if running.
    // We do a best-effort cleanup here.
    if isRunning {
      stopInternal()
    }
  }

  /// Start watching for file system events.
  func start() {
    queue.async { [self] in
      guard !isRunning else { return }
      isRunning = true
      createStream()
    }
  }

  /// Stop watching for file system events.
  func stop() {
    queue.async { [self] in
      guard isRunning else { return }
      stopInternal()
    }
  }

  // MARK: - Private

  private func createStream() {
    let pathsToWatch = [path] as CFArray

    // Context with pointer to self (unretained since we control the lifecycle)
    var context = FSEventStreamContext(
      version: 0,
      info: Unmanaged.passUnretained(self).toOpaque(),
      retain: nil,
      release: nil,
      copyDescription: nil
    )

    let flags = UInt32(
      kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
        | kFSEventStreamCreateFlagNoDefer
    )

    guard
      let newStream = FSEventStreamCreate(
        kCFAllocatorDefault,
        fsEventsCallback,
        &context,
        pathsToWatch,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        0,  // latency — we handle debouncing ourselves
        FSEventStreamCreateFlags(flags)
      )
    else {
      return
    }

    stream = newStream
    FSEventStreamSetDispatchQueue(newStream, queue)
    FSEventStreamStart(newStream)
  }

  private func stopInternal() {
    debounceWork?.cancel()
    debounceWork = nil

    if let stream {
      FSEventStreamStop(stream)
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
    }
    stream = nil
    pendingEvents.removeAll()
    isRunning = false
  }

  /// Called from the FSEvents C callback on our dispatch queue.
  fileprivate func handleRawEvents(_ events: [Event]) {
    pendingEvents.append(contentsOf: events)

    // Cancel any existing debounce timer and start a new one
    debounceWork?.cancel()
    let work = DispatchWorkItem { [self] in
      let batch = pendingEvents
      pendingEvents.removeAll()
      guard !batch.isEmpty else { return }
      handler(batch)
    }
    debounceWork = work
    queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
  }

  static func events(
    paths: [String],
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    count: Int
  ) -> [Event]? {
    guard count >= 0, paths.count >= count else { return nil }

    var events: [Event] = []
    events.reserveCapacity(count)

    for i in 0..<count {
      let flags = EventFlags(rawValue: eventFlags[i])
      events.append(Event(path: paths[i], flags: flags))
    }

    return events
  }
}

// MARK: - FSEvents C Callback

private func fsEventsCallback(
  _ streamRef: ConstFSEventStreamRef,
  _ clientCallBackInfo: UnsafeMutableRawPointer?,
  _ numEvents: Int,
  _ eventPaths: UnsafeMutableRawPointer,
  _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
  _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
  guard let info = clientCallBackInfo else { return }
  let watcher = Unmanaged<FSEventsStream>.fromOpaque(info).takeUnretainedValue()

  // eventPaths is a CFArray of CFString when kFSEventStreamCreateFlagUseCFTypes is set
  let rawPaths = unsafeBitCast(eventPaths, to: NSArray.self)
  guard
    let paths = rawPaths as? [String],
    let events = FSEventsStream.events(paths: paths, eventFlags: eventFlags, count: numEvents)
  else { return }

  watcher.handleRawEvents(events)
}
