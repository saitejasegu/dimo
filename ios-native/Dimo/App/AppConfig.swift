import Foundation

enum AppConfig {
  static var convexURL: String {
    Bundle.main.object(forInfoDictionaryKey: "ConvexURL") as? String ?? ""
  }

  static var workOSClientID: String {
    Bundle.main.object(forInfoDictionaryKey: "WorkOSClientID") as? String ?? ""
  }

  static let workOSRedirectURI = "dimo://callback"
  static let workOSAuthBaseURL = "https://api.workos.com"
  static let workspaceID = "global"

  static var isConfigured: Bool {
    !convexURL.isEmpty && !workOSClientID.isEmpty
      && !convexURL.contains("$(") && !workOSClientID.contains("$(")
  }
}
