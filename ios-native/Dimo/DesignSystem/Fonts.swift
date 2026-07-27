import SwiftUI

enum DimoFont {
  /// `Font.custom` is called for effectively every `Text` in every body pass, so the
  /// resolved values are memoised by (family, size). Guarded by a lock because view
  /// bodies can run off the main actor.
  private static let cacheLock = NSLock()
  private static var cache: [String: Font] = [:]

  private static func font(_ name: String, size: CGFloat) -> Font {
    let key = "\(name)|\(size)"
    cacheLock.lock(); defer { cacheLock.unlock() }
    if let existing = cache[key] { return existing }
    let created = Font.custom(name, size: size)
    cache[key] = created
    return created
  }

  static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
    let name: String
    switch weight {
    case .bold, .heavy, .black: name = "SpaceGrotesk-Bold"
    case .semibold: name = "SpaceGrotesk-SemiBold"
    case .medium: name = "SpaceGrotesk-Medium"
    default: name = "SpaceGrotesk-Medium"
    }
    return font(name, size: size)
  }

  static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    let name: String
    switch weight {
    case .semibold, .bold, .heavy, .black: name = "IBMPlexSans-SemiBold"
    case .medium: name = "IBMPlexSans-Medium"
    default: name = "IBMPlexSans-Regular"
    }
    return font(name, size: size)
  }
}
