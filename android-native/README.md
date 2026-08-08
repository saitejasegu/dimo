# Dimo native Android

Kotlin + Jetpack Compose Android app for Dimo. Shares the existing Convex +
WorkOS backend with the web, Electron, and iOS clients.

`ios-native/` is the sole behavioral reference. Android aims at **core parity**
with iOS except the Email/Gmail/AI suggestions subsystem.

Requires **minSdk 26**, **targetSdk 37**, **JDK 17+** (Temurin 21 recommended).

## Features

- Four primary tabs: Home, Stats, Budgets, Lending (Recurring is reached from
  Home / the expense editor; Settings and Account are stack destinations)
- Local-first Room/SQLite store with Convex sync and WorkOS PKCE sign-in
- Lending writer: address-book contacts, repayments capped to outstanding,
  shareable unsettled-cycle summaries
- CSV import / export compatible with web and iOS
- Multi-currency expenses using Convex `exchangeRates:latest` (ECB snapshot)
- **No Email / Gmail / on-device LLM** — Android does not pull, store, clear, or
  re-upload `emailMessage` entities so iOS-owned email suggestions survive
  Android full cloud replacement

## Setup

```bash
brew install --cask temurin@21
brew install --cask android-commandlinetools   # or Android Studio
# Accept licenses and install platform 36+/37, build-tools, platform-tools

cd android-native
# local.properties (gitignored) must contain:
# sdk.dir=/path/to/Android/sdk
./gradlew :app:assembleProdDebug
```

## CI → Pixel (Play Internal testing)

Pushes to `main` that touch `android-native/**` run
`.github/workflows/android-play-internal.yml`: unit tests, signed
`prodRelease` AAB, upload to the Play Console Internal testing track. One-time
Play Console + keystore + GitHub secrets setup:
[store/ANDROID_PLAY_INTERNAL.md](../store/ANDROID_PLAY_INTERNAL.md).

Product flavors mirror iOS xcconfigs:

| Flavor | Convex URL | WorkOS client |
| --- | --- | --- |
| `prod` (default) | `https://formal-akita-237.convex.cloud` | `client_01KX83VGCS077ZKQSRK9BNSKKK` |
| `dev` | `https://little-bat-382.convex.cloud` | `client_01KX83VG314Y92FTEJX28H23Z9` |

Convex URL and the public WorkOS client ID are expected to be public. Never put
a WorkOS API key or client secret in Android config.

**Manual:** register `dimo://callback` as an allowed redirect URI on the WorkOS
**prod** public client (same callback iOS uses).

Bundle / application id: `app.dimo.android` (`app.dimo.android.dev` for the
`dev` flavor).

## Architecture

| Layer | Path | Notes |
| --- | --- | --- |
| App shell | `app/` | `MainActivity`, `RootView`, `AppConfig` from `BuildConfig` |
| Auth | `auth/` | WorkOS PKCE via Custom Tabs; refresh token in EncryptedSharedPreferences |
| Data | `data/` | Room `dimo-{userId}.db`, typed tables, dirty-key outbox, sanitizer |
| Sync | `sync/` | `SyncCoordinator` + `ConvexSyncTransport` (`dev.convex:android-convexmobile`) |
| Domain | `domain/` | Pure selectors ported from iOS (`DateHelpers`, stats, budgets, CSV, …) |
| Store | `store/` | `AppStore` ViewModel — hydration, drafts, mutations, toasts |
| UI | `features/`, `design/` | Compose screens + Theme / fonts / components |

### Parity rules (must not regress)

1. **Do not destroy iOS-owned email data.** Exclude `emailMessage` from
   `clearWorkspace`, `enqueueFullUpload`, and pull. Android holds no email rows.
2. **Android is a lending writer** (like iOS): group by address-book `contactId`,
   never persist/sync contact photos, cap repayments at outstanding (excluding
   the edited row), reuse `LendSelectors.unsettledTransactions`.
3. Category deletion tombstones linked **transactions** only (native parity with
   iOS; web also tombstones linked recurring).

### Sync cycle

`ensureWorkspaceProfile` → `pullAll` → currency / payment-method backfills →
`enqueueUnsyncedDefaults` → `pushAll` → `pullAll` → purge expired tombstones.

Wire numerics must be JSON doubles. Fresh DBs seed only Cash + default
preferences at logical version zero (`putLocalOnly`).

## Commands

```bash
export JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || echo /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home)"

./gradlew :app:testProdDebugUnitTest
./gradlew :app:assembleProdDebug
./gradlew :app:installProdDebug
adb shell am start -n app.dimo.android/.app.MainActivity
```

See [TESTING.md](TESTING.md) for the unit and emulator checklist.
