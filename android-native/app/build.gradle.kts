plugins {
  id("com.android.application")
  id("org.jetbrains.kotlin.android")
  id("org.jetbrains.kotlin.plugin.compose")
  id("org.jetbrains.kotlin.plugin.serialization")
  id("com.google.devtools.ksp")
}

android {
  namespace = "app.dimo.android"
  compileSdk = 35

  defaultConfig {
    applicationId = "app.dimo.android"
    minSdk = 26
    targetSdk = 35
    versionCode = 1
    versionName = "1.0.0"
    testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

    buildConfigField("String", "CONVEX_URL", "\"https://formal-akita-237.convex.cloud\"")
    buildConfigField("String", "WORKOS_CLIENT_ID", "\"client_01KX83VGCS077ZKQSRK9BNSKKK\"")
    buildConfigField("String", "WORKOS_REDIRECT_URI", "\"dimo://callback\"")
    buildConfigField("String", "WORKOS_AUTH_BASE_URL", "\"https://api.workos.com\"")
  }

  flavorDimensions += "env"
  productFlavors {
    create("prod") {
      dimension = "env"
      buildConfigField("String", "CONVEX_URL", "\"https://formal-akita-237.convex.cloud\"")
      buildConfigField("String", "WORKOS_CLIENT_ID", "\"client_01KX83VGCS077ZKQSRK9BNSKKK\"")
    }
    create("dev") {
      dimension = "env"
      applicationIdSuffix = ".dev"
      versionNameSuffix = "-dev"
      buildConfigField("String", "CONVEX_URL", "\"https://little-bat-382.convex.cloud\"")
      buildConfigField("String", "WORKOS_CLIENT_ID", "\"client_01KX83VG314Y92FTEJX28H23Z9\"")
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

  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }
  kotlinOptions {
    jvmTarget = "17"
  }
  buildFeatures {
    compose = true
    buildConfig = true
  }
  packaging {
    resources {
      excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
  }
}

dependencies {
  val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
  implementation(composeBom)
  androidTestImplementation(composeBom)

  implementation("androidx.core:core-ktx:1.15.0")
  implementation("androidx.activity:activity-compose:1.9.3")
  implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
  implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
  implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
  implementation("androidx.compose.ui:ui")
  implementation("androidx.compose.ui:ui-tooling-preview")
  implementation("androidx.compose.material3:material3")
  implementation("androidx.compose.material:material-icons-extended")
  implementation("androidx.navigation:navigation-compose:2.8.5")
  implementation("androidx.browser:browser:1.8.0")
  implementation("androidx.security:security-crypto:1.1.0-alpha06")

  val room = "2.6.1"
  implementation("androidx.room:room-runtime:$room")
  implementation("androidx.room:room-ktx:$room")
  ksp("androidx.room:room-compiler:$room")

  implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
  implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
  implementation("com.squareup.okhttp3:okhttp:4.12.0")

  implementation("dev.convex:android-convexmobile:0.8.0@aar") {
    isTransitive = true
  }

  debugImplementation("androidx.compose.ui:ui-tooling")
  testImplementation("junit:junit:4.13.2")
  testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
  testImplementation("androidx.room:room-testing:$room")
}
