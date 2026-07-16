import Foundation

enum AppConfig {
  static var convexURL: String {
    Bundle.main.object(forInfoDictionaryKey: "ConvexURL") as? String ?? ""
  }

  static var workOSClientID: String {
    Bundle.main.object(forInfoDictionaryKey: "WorkOSClientID") as? String ?? ""
  }

  static var gmailOAuthClientID: String {
    Bundle.main.object(forInfoDictionaryKey: "GmailOAuthClientID") as? String ?? ""
  }

  static var gmailOAuthRedirectScheme: String {
    Bundle.main.object(forInfoDictionaryKey: "GmailOAuthRedirectScheme") as? String ?? ""
  }

  static var gmailOAuthRedirectURI: String {
    "\(gmailOAuthRedirectScheme):/oauthredirect"
  }

  static var isGmailConfigured: Bool {
    !gmailOAuthClientID.isEmpty
      && !gmailOAuthRedirectScheme.isEmpty
      && !gmailOAuthClientID.contains("REPLACE_ME")
      && !gmailOAuthRedirectScheme.contains("REPLACE_ME")
      && !gmailOAuthClientID.contains("$(")
      && !gmailOAuthRedirectScheme.contains("$(")
  }

  static let workOSRedirectURI = "dimo://callback"
  static let workOSAuthBaseURL = "https://api.workos.com"
  static let workspaceID = "global"
  static let emailRefreshTaskIdentifier = "app.dimo.ios.email-refresh"
  static let emailAnalysisTaskIdentifier = "app.dimo.ios.email-analysis"

  static var isConfigured: Bool {
    !convexURL.isEmpty && !workOSClientID.isEmpty
      && !convexURL.contains("$(") && !workOSClientID.contains("$(")
  }
}
