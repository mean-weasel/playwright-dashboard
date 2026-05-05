enum ExpandedFramePersistencePolicy {
  static let interval = 30

  static func shouldPersist(
    hasPersistedFrame: Bool,
    framesSinceLastPersist: Int
  ) -> Bool {
    !hasPersistedFrame || framesSinceLastPersist >= interval
  }
}
