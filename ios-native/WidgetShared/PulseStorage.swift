import Foundation
import WidgetKit

enum PulseStorage {
  static let groupID = "group.app.dimo.ios"
  static let kind = "DimoSpendingPulse"
  static var defaults: UserDefaults? { UserDefaults(suiteName: groupID) }
  private static var fileURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
      .appendingPathComponent("spending-pulse.json")
  }
  static var period: PulsePeriod {
    get { PulsePeriod(rawValue: defaults?.string(forKey: "pulse.period") ?? "") ?? .week }
    set { defaults?.set(newValue.rawValue, forKey: "pulse.period") }
  }
  static func read() -> PulseSnapshot? {
    guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(PulseSnapshot.self, from: data)
  }
  static func write(_ snapshot: PulseSnapshot) throws {
    guard let url = fileURL else { throw CocoaError(.fileNoSuchFile) }
    let data = try JSONEncoder().encode(snapshot)
    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    WidgetCenter.shared.reloadTimelines(ofKind: kind)
  }
  static func clear() {
    if let url = fileURL { try? FileManager.default.removeItem(at: url) }
    defaults?.removeObject(forKey: "pulse.owner")
    defaults?.removeObject(forKey: "pulse.period")
    WidgetCenter.shared.reloadTimelines(ofKind: kind)
  }
  static func activate(owner: String) {
    if defaults?.string(forKey: "pulse.owner") != owner { clear() }
    defaults?.set(owner, forKey: "pulse.owner")
  }
}
