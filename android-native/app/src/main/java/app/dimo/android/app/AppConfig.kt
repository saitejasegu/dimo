package app.dimo.android.app

import app.dimo.android.BuildConfig

/**
 * Runtime configuration, the Android counterpart of `ios-native/Dimo/App/AppConfig.swift`.
 * iOS reads these from `Info.plist` (fed by the xcconfig files under `Config/`);
 * Android reads them from `BuildConfig` fields set per product flavor.
 */
object AppConfig {
  val convexURL: String = BuildConfig.CONVEX_URL
  val workOSClientID: String = BuildConfig.WORKOS_CLIENT_ID
  val workOSRedirectURI: String = BuildConfig.WORKOS_REDIRECT_URI
  val workOSAuthBaseURL: String = BuildConfig.WORKOS_AUTH_BASE_URL

  val isConfigured: Boolean
    get() = convexURL.isNotBlank() && workOSClientID.isNotBlank()

  // MARK: - Gmail

  val gmailOAuthClientID: String = BuildConfig.GMAIL_OAUTH_CLIENT_ID
  val gmailOAuthRedirectScheme: String = BuildConfig.GMAIL_OAUTH_REDIRECT_SCHEME
  val gmailOAuthRedirectURI: String get() = "$gmailOAuthRedirectScheme:/oauthredirect"

  /**
   * False until a Google Cloud OAuth client for this package + signing key is put
   * in `android-native/gmail.properties`. The Email tab checks this before
   * offering to connect an inbox.
   */
  val isGmailConfigured: Boolean
    get() = gmailOAuthClientID.isNotBlank() &&
      gmailOAuthRedirectScheme.isNotBlank() &&
      !gmailOAuthClientID.contains("REPLACE_ME") &&
      !gmailOAuthRedirectScheme.contains("REPLACE_ME")
}
