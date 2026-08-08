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
    // CI passes -PversionCode / -PversionName so each Play upload is unique.
    versionCode = (findProperty("versionCode") as String?)?.toIntOrNull() ?: 1
    versionName = (findProperty("versionName") as String?) ?: "1.0.0"
    testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

    // Mirrors ios-native AppConfig: Convex URL and the public WorkOS client id
    // are public values; no API key or client secret ever lands here.
    buildConfigField("String", "WORKOS_REDIRECT_URI", "\"dimo://callback\"")
    buildConfigField("String", "WORKOS_AUTH_BASE_URL", "\"https://api.workos.com\"")
  }

  flavorDimensions += "env"
  productFlavors {
    // Values from ios-native/Config/Debug.xcconfig + Release.xcconfig.
    create("prod") {
      dimension = "env"
      isDefault = true
      buildConfigField("String", "CONVEX_URL", "\"https://formal-akita-237.convex.cloud\"")
      buildConfigField("String", "WORKOS_CLIENT_ID", "\"client_01KX83VGCS077ZKQSRK9BNSKKK\"")
    }
    // Values from ios-native/Config/Dev.xcconfig.
    create("dev") {
      dimension = "env"
      applicationIdSuffix = ".dev"
      versionNameSuffix = "-dev"
      buildConfigField("String", "CONVEX_URL", "\"https://little-bat-382.convex.cloud\"")
      buildConfigField("String", "WORKOS_CLIENT_ID", "\"client_01KX83VG314Y92FTEJX28H23Z9\"")
    }
  }

  // CI (and local Play builds) set ANDROID_KEYSTORE_* env vars. Debug builds
  // ignore this and keep using the default debug keystore.
  val uploadKeystorePath = System.getenv("ANDROID_KEYSTORE_PATH")
  val uploadSigningConfigured = !uploadKeystorePath.isNullOrBlank() &&
    !System.getenv("ANDROID_KEYSTORE_PASSWORD").isNullOrBlank() &&
    !System.getenv("ANDROID_KEY_ALIAS").isNullOrBlank() &&
    !System.getenv("ANDROID_KEY_PASSWORD").isNullOrBlank()

  signingConfigs {
    if (uploadSigningConfigured) {
      create("upload") {
        storeFile = file(uploadKeystorePath!!)
        storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
        keyAlias = System.getenv("ANDROID_KEY_ALIAS")
        keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
      }
    }
  }

  buildTypes {
    release {
      isMinifyEnabled = false
      proguardFiles(
        getDefaultProguardFile("proguard-android-optimize.txt"),
        "proguard-rules.pro",
      )
      if (uploadSigningConfigured) {
        signingConfig = signingConfigs.getByName("upload")
      }
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

ksp {
  arg("room.generateKotlin", "true")
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
