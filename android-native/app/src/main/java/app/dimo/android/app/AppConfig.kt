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
}
