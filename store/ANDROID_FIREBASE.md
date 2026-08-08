# Android — Firebase App Distribution

Application id: `app.dimo.android` · native Compose app in `android-native/`

Every commit pushed to `main` that changes `android-native/**` or
`.github/workflows/android-firebase.yml` starts the Android Firebase workflow.
Unit tests and the APK build run in parallel; upload starts only after both
succeed. A newer qualifying push cancels an older in-progress run. The workflow
can also be run manually from GitHub Actions, and every run gets a unique
`versionCode`.

This is the Android counterpart of the iOS TestFlight pipeline in
`.github/workflows/ios-testflight.yml`.

## What you get on the Pixel

1. CI builds a **prodDebug** APK (production Convex + WorkOS).
2. Firebase App Distribution notifies the **Firebase App Tester** app.
3. You tap **Download** on the Pixel — near-automatic, one tap per build
   (Play Store policies do not allow silent install of sideloaded APKs).

## One-time setup

### 1. Firebase project + Android app

1. Open [Firebase Console](https://console.firebase.google.com/) and create or
   pick a project (can be empty — no Google Services JSON is required for this
   debug distribution path).
2. Add an **Android** app with package name `app.dimo.android`.
3. Copy the **App ID** (looks like `1:1234567890:android:abcdef…`).

### 2. Tester group

1. Firebase → **App Distribution** → **Testers & Groups**.
2. Create a group, e.g. `pixel-testers`.
3. Add your Gmail (the one signed into Play / the Pixel).
4. Accept the email invite on the phone.

### 3. Service account

1. Firebase project settings → **Service accounts** → generate a new private
   key (JSON), **or** create a Google Cloud service account with the
   **Firebase App Distribution Admin** role and download its JSON key.
2. Keep the JSON file offline; you will paste it into GitHub Secrets.

### 4. GitHub Actions variables + secret

Repository → **Settings** → **Secrets and variables** → **Actions**.

**Variables**

| Name | Example | Notes |
| --- | --- | --- |
| `FIREBASE_ANDROID_APP_ID` | `1:…:android:…` | From Firebase Android app settings |
| `FIREBASE_TESTER_GROUPS` | `pixel-testers` | Comma-separated group aliases |

**Secrets**

| Name | Value |
| --- | --- |
| `FIREBASE_SERVICE_ACCOUNT` | Full service-account JSON (entire file contents) |

### 5. Phone

1. On the Pixel 8a, install **Firebase App Tester** from the Play Store.
2. Sign in with the invited Gmail.
3. Enable notifications for App Tester so new CI builds surface quickly.

## Manual run

GitHub → **Actions** → **Android Firebase** → **Run workflow**.

## Local equivalent

```bash
cd android-native
./gradlew :app:assembleProdDebug -PversionCode=1001 -PversionName=1.0.0+1001
```

APK path: `app/build/outputs/apk/prod/debug/app-prod-debug.apk`.

## Notes

- Builds are **debug-signed**. Fine for personal / internal testing via App
  Distribution. Play Store / production release still needs a separate upload
  keystore later.
- If the workflow fails with “Missing GitHub Actions configuration”, finish the
  variables/secret steps above.
- iOS remains on TestFlight; this pipeline only covers Android.
