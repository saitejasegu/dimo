# Dimo native iOS

Swift + SwiftUI rewrite of Dimo. Lives alongside the Capacitor `ios/` app and shares the existing Convex + WorkOS backend.

Requires **iOS 26** (native Liquid Glass `TabView`).

## Setup

```bash
brew install xcodegen
cd ios-native
xcodegen generate
open Dimo.xcodeproj
```

Or build from CLI (requires full Xcode; if `xcode-select` points at Command Line Tools, prefix with `DEVELOPER_DIR`):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild -project Dimo.xcodeproj -scheme Dimo \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Config comes from `Config/Debug.xcconfig` / `Config/Release.xcconfig` → Info.plist (`ConvexURL`, `WorkOSClientID`).

Both Debug and Release currently point at Convex **prod** (`formal-akita-237`) + the WorkOS prod client. `Config/Dev.xcconfig` has the Convex dev URL if you need it later.

**Manual:** register `dimo://callback` as an allowed redirect URI on the WorkOS **prod** client (public client + PKCE).

After changing xcconfigs: `xcodegen generate`, then delete the app from the phone and reinstall (old builds keep the previous Info.plist URL).

Bundle id: `app.dimo.ios` (does not collide with Capacitor `app.dimo.expenses`).

## Architecture

- **GRDB** local SQLite (`dimo-{userId}.sqlite`) — entities / outbox / syncMeta / deviceMeta
- **SyncCoordinator** — pull → push → pull, LWW via `LogicalVersion`, Double wire numerics for Convex `v.number()`
- **WorkOS AuthKit PKCE** via `ASWebAuthenticationSession` + Keychain refresh token
- **Domain/** — 1:1 ports of web selectors / CSV / dates / formatting
