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

Every commit pushed to `main` that changes `ios-native/**` or
`.github/workflows/ios-testflight.yml` is built, tested, signed, and uploaded by
the TestFlight workflow. It can also be run manually from GitHub Actions. Each
workflow run gets a unique build number, including re-runs.

### GitHub Actions signing setup (one-time)

1. In App Store Connect, create the Dimo app record for bundle ID
   `app.dimo.ios` if it does not already exist.
2. In Apple Developer → Certificates, Identifiers & Profiles, create an
   **Apple Distribution** certificate and an **App Store Connect** provisioning
   profile for `app.dimo.ios` using that certificate.
3. Import the certificate into Keychain Access. Under **My Certificates**, make
   sure it has its private key, then export it as a password-protected `.p12`.
4. In App Store Connect → Users and Access → Integrations → App Store
   Connect API, create a **team API key** with the **App Manager** role. Download
   the `AuthKey_*.p8` immediately; Apple only offers it once.
5. Add these GitHub Actions variables in the repository's Settings → Secrets
   and variables → Actions → Variables:

   - `APPLE_TEAM_ID`: the 10-character Apple Developer team ID
   - `APPSTORE_ISSUER_ID`: issuer ID shown beside the team API keys
   - `APPSTORE_API_KEY_ID`: key ID for the downloaded `.p8`

6. Add these GitHub Actions repository secrets:

   - `APPSTORE_API_PRIVATE_KEY`: the complete text of `AuthKey_*.p8`
   - `APPSTORE_CERTIFICATES_FILE_BASE64`: base64-encoded `.p12`
   - `APPSTORE_CERTIFICATES_PASSWORD`: the `.p12` export password

With GitHub CLI authenticated for this repository, steps 5–6 can be entered as:

```bash
gh variable set APPLE_TEAM_ID
gh variable set APPSTORE_ISSUER_ID
gh variable set APPSTORE_API_KEY_ID
gh secret set APPSTORE_API_PRIVATE_KEY < /path/to/AuthKey_KEYID.p8
base64 -i /path/to/ios_distribution.p12 | gh secret set APPSTORE_CERTIFICATES_FILE_BASE64
gh secret set APPSTORE_CERTIFICATES_PASSWORD
```

Do not commit the `.p8`, `.p12`, or their passwords. After configuring the six
values, run **iOS TestFlight** once with Actions → iOS TestFlight → Run
workflow. A successful run waits until Apple finishes processing the upload.

In App Store Connect → TestFlight, create an internal testing group, add the
testers, and enable automatic distribution so each processed build becomes
available without another CI step. Install via TestFlight and smoke-test: add
expense, budgets, lending, and account sync.

The workflow uploads builds to TestFlight; it does not submit every commit for
public App Store review. App Store review requires a prepared store-version
record and should be submitted only after choosing the TestFlight build to
release. External TestFlight groups may also require an initial TestFlight App
Review.

## 4. Store listing assets

Copy from `store/listing.json` into App Store Connect:

| Field | Source |
|-------|--------|
| Name / subtitle | `listing.json` |
| Description / keywords | `listing.json` |
| Privacy Policy URL | `https://dimoapp.xyz/privacy` |
| Support URL | `https://dimoapp.xyz/support` |
| Terms of Service URL | `https://dimoapp.xyz/terms` (if Connect asks) |
| App Privacy | Copy the answers in `APP_PRIVACY.md` |
| Icon | `store/AppIcon-1024.png` |
| Screenshots | Capture on Simulator into `store/screenshots/` |

**Public URLs:** support `https://dimoapp.xyz/support`, privacy `https://dimoapp.xyz/privacy`, terms `https://dimoapp.xyz/terms`. Redeploy after edits (`npm run build` → host `out/`).

**Google OAuth branding:** see `store/GOOGLE_OAUTH.md` (public homepage, logo upload, Search Console ownership).

## 5. Submit for review

1. App Store Connect → your app → iOS version
2. Select the TestFlight build
3. Complete Age Rating, Pricing (Free), Review Information (contact + demo notes)
4. Complete App Privacy using `store/APP_PRIVACY.md`
5. Add for Review → Submit

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
