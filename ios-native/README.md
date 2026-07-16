# Dimo native iOS

Swift + SwiftUI iOS app for Dimo. Shares the existing Convex + WorkOS backend with the web, Electron, and Android clients.

Requires **iOS 26** (native Liquid Glass `TabView`).

## Features

- Five primary tabs: Home, Stats, Recurring, Budgets, Lending
- Local-first GRDB store with Convex sync and WorkOS PKCE sign-in
- Lending writer: address-book contacts, repayments capped to outstanding, shareable unsettled-cycle summaries
- CSV import / export compatible with the web client
- Optional Email suggestions: read-only Gmail on-device, then Local Gemma or OpenRouter analysis (user-chosen). Analyzed suggestions sync as `emailMessage` (including body); Gmail/OpenRouter credentials stay device-only

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
  -sdk iphonesimulator -destination "generic/platform=iOS Simulator" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build CODE_SIGNING_ALLOWED=NO
```

Named simulator example (needs an installed runtime):

```bash
xcodebuild -project Dimo.xcodeproj -scheme Dimo \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Config comes from `Config/Debug.xcconfig` / `Config/Release.xcconfig` → Info.plist (`ConvexURL`, `WorkOSClientID`, `GmailOAuthClientID`, `GmailOAuthRedirectScheme`).

Both Debug and Release currently point at Convex **prod** (`formal-akita-237`) + the WorkOS prod client. `Config/Dev.xcconfig` has the Convex dev URL if you need it later.

**Manual:** register `dimo://callback` as an allowed redirect URI on the WorkOS **prod** client (public client + PKCE).

For Email suggestions, replace `GMAIL_OAUTH_CLIENT_ID` and
`GMAIL_OAUTH_REDIRECT_SCHEME` in `Config/Shared.xcconfig` with a Google iOS OAuth
client and its reversed client-ID scheme. Enable the Gmail API and request
`openid email https://www.googleapis.com/auth/gmail.readonly`. Production use
requires Google's restricted-scope verification; configure the OAuth redirect
as `<reversed-client-id>:/oauthredirect`. `GemmaModelManifest.json` uses a
commit-pinned, anonymously downloadable Hugging Face mirror of the LiteRT
Community artifact. The app verifies the official artifact's exact byte count
and SHA-256 before installation, so a hosted-file substitution is rejected.
Changing the mirror, commit, or artifact requires a bundled manifest update and
a new app release.

Email analysis has no default provider. Each signed-in user chooses either the
downloaded Local Gemma model or OpenRouter in Email settings. OpenRouter uses a
user-supplied API key stored in a device-only, user-scoped Keychain item;
analysis requests go from the iPhone to OpenRouter (not via Convex). Analyzed
suggestions, including the full normalized email body, sync through Convex as
native-owned `emailMessage` entities so they restore across devices. Gmail OAuth
tokens never enter the sync payload. The model catalog, pricing,
structured-output support, and ZDR availability are read from OpenRouter at
runtime. Do not add an OpenRouter key to an xcconfig, Info.plist, source file,
database, or Dimo sync payload.

LiteRT-LM's Swift wrapper is pinned to upstream tag `v0.13.0` under
`Packages/LiteRTLM`. This small packaging shim is necessary because the
upstream 0.13.0 remote product declares an unsafe linker flag that Xcode refuses
for application targets; `Packages/LiteRTLM/UPSTREAM.md` records the exact
commit, binary checksum, and removal path.

After changing xcconfigs: `xcodegen generate`, then delete the app from the phone and reinstall (old builds keep the previous Info.plist URL).

Bundle id: `app.dimo.ios`.

## Architecture

- **GRDB** local SQLite (`dimo-{userId}.sqlite`) — entities / outbox / syncMeta / deviceMeta
- **SyncCoordinator** — ensure workspace profile → pull → push → pull, LWW via `LogicalVersion`, Double wire numerics for Convex `v.number()`
- **WorkOS AuthKit PKCE** via `ASWebAuthenticationSession` + Keychain refresh token
- **Domain/** — 1:1 ports of web selectors / CSV / dates / formatting
- **Email/** — Gmail OAuth + on-device parse → Local Gemma / OpenRouter analysis; analyzed `emailMessage` rows sync with body; OAuth/OpenRouter secrets stay device-only
- Category delete tombstones linked transactions only (native parity with Android; web also tombstones linked recurring)
- Native **Sync now** is ordinary sync; full cloud replacement is a separate explicit action
- Domain tests: `DimoTests/DomainTests.swift`
