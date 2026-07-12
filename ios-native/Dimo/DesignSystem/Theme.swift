import SwiftUI
import UIKit

enum Theme {
  static let ink = Color(uiColor: .dynamic(light: 0x14231C, dark: 0xF2F7F4))
  static let inkDeep = Color(uiColor: .dynamic(light: 0x0D1512, dark: 0x0D1512))
  static let canvas = Color(uiColor: .dynamic(light: 0xF5F8F6, dark: 0x0C1210))
  static let canvasDeep = Color(uiColor: .dynamic(light: 0xEEF2F0, dark: 0x151E1A))
  static let surface = Color(uiColor: .dynamic(light: 0xFFFFFF, dark: 0x1A2620))
  static let popup = Color(uiColor: .dynamic(light: 0xFFFFFF, dark: 0x24332C))
  static let line = Color(uiColor: .dynamic(light: 0xE4EAE7, dark: 0x51665C))
  static let lineSoft = Color(uiColor: .dynamic(light: 0xF0F3F1, dark: 0x35453D))
  static let hairline = Color(uiColor: .dynamic(light: 0xDBE4DF, dark: 0x6A8076))
  static let muted = Color(uiColor: .dynamic(light: 0x7C8A84, dark: 0xB4C4BB))
  static let faint = Color(uiColor: .dynamic(light: 0xA3AEA8, dark: 0x95A69D))
  static let body = Color(uiColor: .dynamic(light: 0x5F6D67, dark: 0xD0DBD5))
  static let green = Color(uiColor: .dynamic(light: 0x1F9D63, dark: 0x4FD598))
  static let greenDeep = Color(uiColor: .dynamic(light: 0x1B8B58, dark: 0x3CC184))
  static let greenSoft = Color(uiColor: .dynamic(light: 0xE6F4EC, dark: 0x153727))
  static let greenBright = Color(hex: 0x4FD598)
  static let bar = Color(uiColor: .dynamic(light: 0xCFE6D9, dark: 0x254C39))
  static let barSoft = Color(uiColor: .dynamic(light: 0x9FCEB5, dark: 0x37684E))
  static let warn = Color(uiColor: .dynamic(light: 0xD97B5A, dark: 0xF0A080))
  static let danger = Color(uiColor: .dynamic(light: 0xC4573C, dark: 0xF08B72))
  static let dangerSoft = Color(uiColor: .dynamic(light: 0xFDF3F0, dark: 0x3A201C))
  static let dangerLine = Color(uiColor: .dynamic(light: 0xF2D9D3, dark: 0x653329))
  static let dangerHover = Color(uiColor: .dynamic(light: 0xB04A33, dark: 0xFF9B82))
  static let disabled = Color(uiColor: .dynamic(light: 0xC3CDC7, dark: 0x879990))
  static let toggleOff = Color(uiColor: .dynamic(light: 0xD7DED9, dark: 0x39473F))
  static let onGreen = Color(uiColor: .dynamic(light: 0xFFFFFF, dark: 0x0D1512))

  // Dark hero card / sidebar palette — fixed across light and dark, matching the web tokens.
  static let inverse = Color(hex: 0x14231C)
  static let sideText = Color(hex: 0xEAF5EF)
  static let sideMuted = Color(hex: 0x8BA699)
  static let sideSub = Color(hex: 0x7D968A)

  static func colorScheme(for preference: ThemePreference) -> ColorScheme? {
    switch preference {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }
}

extension Color {
  init(hex: UInt32, opacity: Double = 1) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: opacity
    )
  }
}

extension UIColor {
  static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
    UIColor { traits in
      let hex = traits.userInterfaceStyle == .dark ? dark : light
      return UIColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
      )
    }
  }
}
