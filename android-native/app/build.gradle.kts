// `java` inside the android block resolves to Gradle's java extension, so
// Properties is imported rather than fully qualified at the use site.
import java.util.Properties

// AGP 9 has built-in Kotlin support, so `org.jetbrains.kotlin.android` must not
// be applied. Compose / serialization / KSP stay as separate plugins.
plugins {
  alias(libs.plugins.android.application)
  alias(libs.plugins.kotlin.compose)
  alias(libs.plugins.kotlin.serialization)
  alias(libs.plugins.ksp)
}

android {
  namespace = "app.dimo.android"
  compileSdk = 37

  defaultConfig {
    applicationId = "app.dimo.android"
    minSdk = 26
    targetSdk = 37
    versionCode = 1
    versionName = "1.0.0"
    testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

    // Mirrors ios-native AppConfig: Convex URL and the public WorkOS client id
    // are public values; no API key or client secret ever lands here.
    buildConfigField("String", "WORKOS_REDIRECT_URI", "\"dimo://callback\"")
    buildConfigField("String", "WORKOS_AUTH_BASE_URL", "\"https://api.workos.com\"")
  }

  // Gmail uses its own installed-app OAuth client, separate from WorkOS. Provision
  // one per flavor in Google Cloud for this package name + signing SHA-1 and put
  // the values in `gmail.properties` (gitignored, see android-native/README.md).
  // Until then `AppConfig.isGmailConfigured` is false and the Email tab shows its
  // "not configured" state instead of launching a broken consent screen.
  val gmailProperties = Properties().apply {
    val file = rootProject.file("gmail.properties")
    if (file.exists()) file.inputStream().use { load(it) }
  }

  flavorDimensions += "env"
  productFlavors {
    // Values from ios-native/Config/Debug.xcconfig + Release.xcconfig.
    create("prod") {
      dimension = "env"
      isDefault = true
      buildConfigField("String", "CONVEX_URL", "\"https://formal-akita-237.convex.cloud\"")
      buildConfigField("String", "WORKOS_CLIENT_ID", "\"client_01KX83VGCS077ZKQSRK9BNSKKK\"")
      applyGmailConfig(gmailProperties, "prod")
    }
    // Values from ios-native/Config/Dev.xcconfig.
    create("dev") {
      dimension = "env"
      applicationIdSuffix = ".dev"
      versionNameSuffix = "-dev"
      buildConfigField("String", "CONVEX_URL", "\"https://little-bat-382.convex.cloud\"")
      buildConfigField("String", "WORKOS_CLIENT_ID", "\"client_01KX83VG314Y92FTEJX28H23Z9\"")
      applyGmailConfig(gmailProperties, "dev")
    }
  }

  buildTypes {
    release {
      isMinifyEnabled = false
      proguardFiles(
        getDefaultProguardFile("proguard-android-optimize.txt"),
        "proguard-rules.pro",
      )
    }
  }

  buildFeatures {
    compose = true
    buildConfig = true
  }

  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }

  packaging {
    resources {
      excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
  }

  testOptions {
    unitTests {
      isIncludeAndroidResources = true
    }
  }
}

kotlin {
  compilerOptions {
    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
  }
}

/**
 * Wires one flavor's Gmail OAuth client into BuildConfig and the manifest.
 *
 * The redirect scheme must also reach `AndroidManifest.xml`, because Google's
 * installed-app flow redirects to `{reversed-client-id}:/oauthredirect` and the
 * activity has to declare that scheme to receive it.
 */
fun com.android.build.api.dsl.ApplicationProductFlavor.applyGmailConfig(
  properties: Properties,
  flavor: String,
) {
  val clientId = properties.getProperty("$flavor.gmailOAuthClientId").orEmpty()
  // Google's reversed client id doubles as the redirect scheme.
  val scheme = properties.getProperty("$flavor.gmailOAuthRedirectScheme").orEmpty().ifEmpty {
    clientId.substringBefore(".apps.googleusercontent.com").takeIf { it != clientId }
      ?.let { "com.googleusercontent.apps.$it" }
      .orEmpty()
  }
  buildConfigField("String", "GMAIL_OAUTH_CLIENT_ID", "\"$clientId\"")
  buildConfigField("String", "GMAIL_OAUTH_REDIRECT_SCHEME", "\"$scheme\"")
  // A blank scheme would make the intent-filter unmergeable, so an unconfigured
  // build registers an inert placeholder that Google will never redirect to.
  manifestPlaceholders["gmailRedirectScheme"] =
    scheme.ifEmpty { "app.dimo.android.gmail.unconfigured" }
}

ksp {
  arg("room.generateKotlin", "true")
  // Exported schemas are what `EmailMigrationTest` replays 1 -> 2 against, and
  // they are the reference for the hand-written DDL in `Migrations.kt`.
  arg("room.schemaLocation", "$projectDir/schemas")
}

dependencies {
  implementation(platform(libs.compose.bom))
  androidTestImplementation(platform(libs.compose.bom))

  implementation(libs.androidx.core.ktx)
  implementation(libs.androidx.activity.compose)
  implementation(libs.androidx.lifecycle.runtime.ktx)
  implementation(libs.androidx.lifecycle.runtime.compose)
  implementation(libs.androidx.lifecycle.viewmodel.compose)

  implementation(libs.compose.ui)
  implementation(libs.compose.ui.graphics)
  implementation(libs.compose.ui.tooling.preview)
  implementation(libs.compose.material3)
  implementation(libs.compose.material.icons.extended)

  implementation(libs.androidx.navigation.compose)
  implementation(libs.androidx.browser)
  implementation(libs.androidx.security.crypto)
  implementation(libs.androidx.datastore.preferences)

  implementation(libs.room.runtime)
  implementation(libs.room.ktx)
  ksp(libs.room.compiler)

  implementation(libs.kotlinx.coroutines.android)
  implementation(libs.kotlinx.serialization.json)
  implementation(libs.okhttp)

  implementation(libs.convexmobile) {
    isTransitive = true
  }

  debugImplementation(libs.compose.ui.tooling)

  testImplementation(libs.junit)
  testImplementation(libs.kotlinx.coroutines.test)
  testImplementation(libs.robolectric)
  testImplementation(libs.androidx.test.core)
  testImplementation(libs.room.testing)
}
