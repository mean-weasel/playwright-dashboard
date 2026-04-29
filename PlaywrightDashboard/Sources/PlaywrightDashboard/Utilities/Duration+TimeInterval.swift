import Foundation

extension Duration {
  var timeInterval: TimeInterval {
    let durationComponents = self.components
    return TimeInterval(durationComponents.seconds)
      + TimeInterval(durationComponents.attoseconds) / 1_000_000_000_000_000_000
  }
}
