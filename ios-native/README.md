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

Config comes from `Config/Shared.xcconfig` → Info.plist (`ConvexURL`, `WorkOSClientID`).

**Manual:** register `dimo://callback` as an allowed redirect URI in the WorkOS dashboard (public client + PKCE).

Bundle id: `app.dimo.ios` (does not collide with Capacitor `app.dimo.expenses`).

## Architecture

- **GRDB** local SQLite (`dimo-{userId}.sqlite`) — entities / outbox / syncMeta / deviceMeta
- **SyncCoordinator** — pull → push → pull, LWW via `LogicalVersion`, Double wire numerics for Convex `v.number()`
- **WorkOS AuthKit PKCE** via `ASWebAuthenticationSession` + Keychain refresh token
- **Domain/** — 1:1 ports of web selectors / CSV / dates / formatting
