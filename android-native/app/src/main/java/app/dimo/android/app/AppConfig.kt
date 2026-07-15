package app.dimo.android.app

import app.dimo.android.BuildConfig

object AppConfig {
  val convexUrl: String get() = BuildConfig.CONVEX_URL
  val workOSClientId: String get() = BuildConfig.WORKOS_CLIENT_ID
  val workOSRedirectUri: String get() = BuildConfig.WORKOS_REDIRECT_URI
  val workOSAuthBaseUrl: String get() = BuildConfig.WORKOS_AUTH_BASE_URL
  val workspaceId: String = "global"

  val isConfigured: Boolean
    get() = convexUrl.isNotBlank() &&
      workOSClientId.isNotBlank() &&
      !convexUrl.contains("$(") &&
      !workOSClientId.contains("$(")
}
