# Dimo native iOS

Swift + SwiftUI iOS app for Dimo. Shares the existing Convex + WorkOS backend with the web and Electron clients.

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
user-supplied API key stored in a device-only, user-scoped Keychain item; email
content is sent directly from the iPhone to OpenRouter and never through
Convex. The model catalog, pricing, structured-output support, and ZDR
availability are read from OpenRouter at runtime. Do not add an OpenRouter key
to an xcconfig, Info.plist, source file, database, or Dimo sync payload.

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
