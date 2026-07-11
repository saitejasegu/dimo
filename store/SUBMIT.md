# App Store — Dimo

Bundle ID: `app.dimo.expenses` · Version: `1.0` · Build: `1`

## 1. Prerequisites (one-time)

- [ ] Apple Developer Program membership ($99/year)
- [ ] Install **full Xcode** from the Mac App Store (Command Line Tools alone is not enough)
- [ ] Open Xcode once → Settings → Accounts → add your Apple ID
- [ ] Agree to Xcode license / install extra components if prompted

## 2. Build & open in Xcode

```bash
npm run ios
```

This runs `next build`, syncs into `ios/`, and opens the Xcode workspace.

In Xcode:

1. Select the **App** target → **Signing & Capabilities**
2. Team: your Apple Developer team
3. Confirm Bundle Identifier `app.dimo.expenses`
4. Destination: a simulator or your iPhone
5. Product → Run (⌘R) to verify

## 3. TestFlight

1. Product → Archive
2. Organizer → Distribute App → App Store Connect → Upload
3. In [App Store Connect](https://appstoreconnect.apple.com): create the app if needed (bundle ID must match)
4. Open TestFlight → wait for processing → add internal testers
5. Install via TestFlight and smoke-test: add expense, budgets, sheets, account

## 4. Store listing assets

Copy from `store/listing.json` into App Store Connect:

| Field | Source |
|-------|--------|
| Name / subtitle | `listing.json` |
| Description / keywords | `listing.json` |
| Privacy Policy URL | Host `/privacy` (see below), then paste URL |
| App Privacy | “Data Not Collected” for v1 |
| Icon | `store/AppIcon-1024.png` (also wired in Xcode asset catalog) |
| Screenshots | Capture on Simulator (File → Save Screen) into `store/screenshots/` |

**Privacy URL:** deploy the static site (`npm run build` → host `out/`) so `https://YOUR_DOMAIN/privacy` is public, then put that URL in Connect. Update the contact email on the privacy page before submit.

## 5. Submit for review

1. App Store Connect → your app → iOS version 1.0
2. Select the TestFlight build
3. Complete Age Rating, Pricing (Free), Review Information (contact + demo notes)
4. Review notes tip: “Personal expense tracker. No login. Sample data included.”
5. Add for Review → Submit

## 6. After feedback

- Fix rejection items in the web/Capacitor app
- Bump `CURRENT_PROJECT_VERSION` (build number) in Xcode for each upload
- `npm run ios` → Archive → Upload → submit again

## Useful commands

```bash
npm run build      # static web export → out/
npm run cap:sync   # build + sync into ios/
npm run ios        # sync + open Xcode
```
