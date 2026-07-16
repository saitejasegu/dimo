# Dimo Android

Local-first native Android client with feature parity to `ios-native/` (minus iOS-only Email / Gmail suggestions).

## Features

- Primary tabs: Home, Stats, Budgets, Lending (plus Settings / Account overlays)
- Recurring bills are reached from Home / the expense editor (not a fifth tab)
- Local-first Room store with Convex sync and WorkOS PKCE sign-in
- Lending writer: address-book contacts, repayments capped to outstanding, shareable unsettled-cycle summaries
- CSV import / export compatible with web and iOS

## Stack

- Kotlin + Jetpack Compose + Material 3
- Room / SQLite (account-scoped `dimo-{userId}.db`)
- WorkOS public-client PKCE (`dimo://callback`)
- Convex Android (`dev.convex:android-convexmobile`) against the existing sync API

## Layout

```
android-native/
  app/src/main/java/app/dimo/android/
    app/       Application, MainActivity, RootView, config
    auth/      WorkOS PKCE + Convex AuthProvider
    data/      Entities, Room, repository, sanitizer
    sync/      SyncCoordinator + wire helpers
    store/     AppStore UI orchestration
    domain/    Selectors, dates, CSV, formatting
    design/    Theme + shared components
    features/  Screens and sheets
```

## Configuration

Product flavors:

| Flavor | Convex | WorkOS client |
| --- | --- | --- |
| `prod` (default) | `https://formal-akita-237.convex.cloud` | `client_01KX83VGCS077ZKQSRK9BNSKKK` |
| `dev` | `https://little-bat-382.convex.cloud` | `client_01KX83VG314Y92FTEJX28H23Z9` |

Register redirect URI `dimo://callback` on the WorkOS public client used for Android.

## Build

Requires Android SDK (API 35) and NDK for ConvexMobile AAR.

```bash
cd android-native
# create local.properties with sdk.dir=/path/to/Android/sdk
./gradlew :app:assembleProdDebug
./gradlew :app:testProdDebugUnitTest
```

Manual emulator / device checks: [TESTING.md](TESTING.md).

## Sync contract

Uses existing Convex functions only (no backend changes):

- `sync:currentRevision`
- `sync:pull`
- `sync:push`
- `sync:ensureWorkspaceProfile`
- `sync:clearWorkspace`

Numeric wire fields are encoded as floating JSON numbers (same constraint as iOS `Double` encoding).

## Platform rules

- Android is a lending writer (like iOS). Contacts group by `contactId`; photos never sync.
- Category delete tombstones linked transactions only (native parity).
- Fresh DB seeds Cash + preferences at logical version zero.
- Native **Sync now** is ordinary sync; full cloud replacement is a separate explicit action.
- Sign-out deletes all local `dimo-*.db` files.
- Domain unit tests live under `app/src/test/java/app/dimo/android/domain/`.
