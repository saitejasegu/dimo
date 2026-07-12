import SwiftUI

enum DimoFont {
  static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
    let name: String
    switch weight {
    case .bold, .heavy, .black: name = "SpaceGrotesk-Bold"
    case .semibold: name = "SpaceGrotesk-SemiBold"
    case .medium: name = "SpaceGrotesk-Medium"
    default: name = "SpaceGrotesk-Medium"
    }
    return Font.custom(name, size: size)
  }

  static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    let name: String
    switch weight {
    case .semibold, .bold, .heavy, .black: name = "IBMPlexSans-SemiBold"
    case .medium: name = "IBMPlexSans-Medium"
    default: name = "IBMPlexSans-Regular"
    }
    return Font.custom(name, size: size)
  }
}
