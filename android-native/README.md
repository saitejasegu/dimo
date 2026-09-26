# Dimo native Android

Kotlin + Jetpack Compose Android app for Dimo. Shares the existing Convex +
WorkOS backend with the web, Electron, and iOS clients.

`ios-native/` is the sole behavioral reference. Android aims at **core parity**
with iOS, including the Email/Gmail/AI suggestions subsystem (see
`FEATURE-PARITY.md` §5.1 for the deliberate differences).

Requires **minSdk 26**, **targetSdk 37**, **JDK 17+** (Temurin 21 recommended).

## Features

- Five primary tabs: Home, Stats, Budgets, Lending, Email (Recurring is reached
  from Home / the expense editor; Settings and Account are stack destinations)
- Local-first Room/SQLite store with Convex sync and WorkOS PKCE sign-in
- Lending writer: typed names or a Dimo email (no address book), repayments capped to outstanding,
  shareable unsettled-cycle summaries
- CSV import / export compatible with web and iOS
- Multi-currency expenses using Convex `exchangeRates:latest` (ECB snapshot)
- **Email / Gmail suggestions** — Gmail scan, OpenRouter analysis, purchase and
  refund review. Android is an `emailMessage` writer and participates in pull,
  push, full upload and `clearWorkspace`. Gmail OAuth needs `gmail.properties`
  (see `gmail.properties.example`); without it `AppConfig.isGmailConfigured` is
  false and the tab explains what is missing

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

1. **Keep the email clear/upload pair symmetric.** `emailMessage` is included in
   `clearWorkspace`, `enqueueFullUpload` and pull. Full replacement clears *and*
   re-uploads, so narrowing only one side would destroy the user's suggestions.
2. **Android is a lending writer** (like iOS): group by `contactId`
   (no address-book access), cap repayments at outstanding (excluding
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
