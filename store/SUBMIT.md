# App Store — Dimo

Bundle ID: `app.dimo.ios` · native SwiftUI app in `ios-native/`

## 1. Prerequisites (one-time)

- [ ] Apple Developer Program membership ($99/year)
- [ ] Install **full Xcode** from the Mac App Store (Command Line Tools alone is not enough)
- [ ] Open Xcode once → Settings → Accounts → add your Apple ID
- [ ] Agree to Xcode license / install extra components if prompted
- [ ] Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## 2. Build & open in Xcode

```bash
cd ios-native
xcodegen generate
open Dimo.xcodeproj
```

In Xcode:

1. Select the **Dimo** target → **Signing & Capabilities**
2. Team: your Apple Developer team
3. Confirm Bundle Identifier `app.dimo.ios`
4. Destination: a simulator or your iPhone
5. Product → Run (⌘R) to verify

Config comes from `ios-native/Config/*.xcconfig` (`ConvexURL`, `WorkOSClientID`). Register `dimo://callback` as an allowed redirect on the WorkOS client.

## 3. TestFlight

1. Product → Archive
2. Organizer → Distribute App → App Store Connect → Upload
3. In [App Store Connect](https://appstoreconnect.apple.com): create the app if needed (bundle ID must match)
4. Open TestFlight → wait for processing → add internal testers
5. Install via TestFlight and smoke-test: add expense, budgets, lending, account sync

## 4. Store listing assets

Copy from `store/listing.json` into App Store Connect:

| Field | Source |
|-------|--------|
| Name / subtitle | `listing.json` |
| Description / keywords | `listing.json` |
| Privacy Policy URL | Host `/privacy` (see below), then paste URL |
| App Privacy | Reflect WorkOS auth + Convex sync as applicable |
| Icon | `store/AppIcon-1024.png` |
| Screenshots | Capture on Simulator into `store/screenshots/` |

**Privacy URL:** deploy the static site (`npm run build` → host `out/`) so `https://YOUR_DOMAIN/privacy` is public, then put that URL in Connect.

## 5. Submit for review

1. App Store Connect → your app → iOS version
2. Select the TestFlight build
3. Complete Age Rating, Pricing (Free), Review Information (contact + demo notes)
4. Add for Review → Submit

## 6. After feedback

- Fix rejection items in `ios-native/`
- Bump build number in Xcode (or project.yml) for each upload
- Archive → Upload → submit again

## Useful commands

```bash
cd ios-native && xcodegen generate   # regenerate Xcode project
open ios-native/Dimo.xcodeproj       # open in Xcode
npm run build                        # static web export → out/ (privacy page, etc.)
```
