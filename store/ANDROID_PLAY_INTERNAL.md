# Android — Play Internal testing

Application id: `app.dimo.android` · native Compose app in `android-native/`

Every commit pushed to `main` that changes `android-native/**` or
`.github/workflows/android-play-internal.yml` starts the Play Internal
workflow. Unit tests and a signed `prodRelease` AAB run in parallel; upload
starts only after both succeed. A newer qualifying push cancels an older
in-progress run. The workflow can also be run manually from GitHub Actions, and
every run gets a unique `versionCode`.

This is the Android counterpart of the iOS TestFlight pipeline in
`.github/workflows/ios-testflight.yml`.

## What you get on the Pixel

1. CI builds a **signed prodRelease AAB** (production Convex + WorkOS).
2. The build is published to the Play Console **Internal testing** track.
3. On the Pixel, open the internal-testing opt-in link once, then install /
   update **Dimo** from the Play Store like a normal app (no Firebase App
   Tester required).

Play may take a few minutes to make a new build available after upload.

## One-time setup

### 1. Play Console app

1. Pay the one-time Google Play developer fee if you have not already.
2. Create an app with package name **`app.dimo.android`**.
3. Fill the minimum store listing (title, short description, icon, screenshots)
   so the app is not an empty shell — Internal testing still needs a listing.
4. Create an **Internal testing** track release once manually if prompted
   (first-time Console setup). After that, CI owns subsequent uploads.

### 2. Upload keystore (keep forever)

Generate a dedicated upload key (do this once; losing it blocks updates):

```bash
keytool -genkeypair -v \
  -keystore dimo-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias dimo-upload \
  -storepass 'CHOOSE_A_STRONG_PASSWORD' \
  -keypass 'CHOOSE_A_STRONG_PASSWORD' \
  -dname 'CN=Dimo, OU=Mobile, O=Dimo, L=Unknown, ST=Unknown, C=US'
```

Base64-encode the keystore for GitHub:

```bash
base64 -i dimo-upload.jks | pbcopy   # macOS
# or: base64 -w0 dimo-upload.jks
```

Register the matching **upload certificate** in Play Console → Setup → App
signing (Play App Signing) when creating the first release.

### 3. Play Developer API service account

1. In Google Cloud Console (linked to the Play developer account), create a
   service account and download its JSON key.
2. In Play Console → Users and permissions, invite that service account email
   with permission to **Release apps to testing tracks** (and view app info).
3. Accept / activate the user if required.

### 4. Internal testers (your Pixel)

1. Play Console → Testing → Internal testing → Testers.
2. Create an email list and add your Gmail.
3. Copy the **opt-in URL** and open it once on the Pixel while signed into that
   Gmail. After opting in, Dimo appears under Play Store → your profile →
   Manage apps & device / testing apps.

### 5. GitHub Actions secrets

Repository → **Settings** → **Secrets and variables** → **Actions** → Secrets:

| Secret | Value |
| --- | --- |
| `PLAY_SERVICE_ACCOUNT_JSON` | Full Play API service-account JSON |
| `ANDROID_KEYSTORE_BASE64` | Base64 of `dimo-upload.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | e.g. `dimo-upload` |
| `ANDROID_KEY_PASSWORD` | Key password (often same as store) |

## Manual run

GitHub → **Actions** → **Android Play Internal** → **Run workflow**.

## Local equivalent

```bash
export ANDROID_KEYSTORE_PATH=/absolute/path/to/dimo-upload.jks
export ANDROID_KEYSTORE_PASSWORD=…
export ANDROID_KEY_ALIAS=dimo-upload
export ANDROID_KEY_PASSWORD=…

cd android-native
./gradlew :app:bundleProdRelease \
  -PversionCode=1001 \
  -PversionName=1.0.0+1001
```

AAB path: `app/build/outputs/bundle/prodRelease/app-prod-release.aab`.

## Notes

- First Console / API upload sometimes needs a one-time manual Internal testing
  release; after that CI uses `status: completed` with
  `changesNotSentForReview: true`.
- Never commit the `.jks` or service-account JSON. Treat them like the iOS
  distribution certificate.
- iOS remains on TestFlight; this pipeline only covers Android.
