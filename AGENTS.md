<!-- convex-ai-start -->

This project uses [Convex](https://convex.dev) as its backend.

When working on Convex code, **always read
`convex/_generated/ai/guidelines.md` first** for important guidelines on
how to correctly use Convex APIs and patterns. The file contains rules that
override what you may have learned about Convex from training data.

Convex agent skills for common tasks can be installed by running
`npx convex ai-files install`.

<!-- convex-ai-end -->

# Dimo at a glance

Dimo is a local-first personal spending tracker for expenses, categories and
budgets, payment methods, recurring bills, stats, CSV import/export, lending, and
account preferences. It has four clients sharing one authenticated Convex
backend:

| Surface | Runtime and local store | Entry points |
| --- | --- | --- |
| Web | Next.js 16, React 19, Tailwind 4, Dexie/IndexedDB | `app/page.tsx`, `app/auth/AuthRoot.tsx` |
| Desktop | Hardened Electron wrapper around the static web export | `electron/main.mjs`, `electron/preload.cjs` |
| iOS | SwiftUI, GRDB/SQLite, iOS 26+ | `ios-native/Dimo/App/DimoApp.swift`, `RootView.swift` |
| Android | Kotlin, Jetpack Compose, Room/SQLite, API 26+ | `android-native/` → `app/MainActivity.kt`, `RootView.kt` |
| Cloud | Convex sync API authenticated by WorkOS AuthKit | `convex/schema.ts`, `values.ts`, `sync.ts`, `auth.config.ts` |

Next.js uses `output: "export"` and produces `out/`; do not add API routes,
server actions, or runtime server dependencies without redesigning Electron.
`AuthRoot` selects responsive mobile or desktop web UI at 900 px. Product
navigation is reducer state rather than URL routes. Electron has no separate
data layer and exposes only platform metadata through its preload bridge.

The main product destinations are Home/Activity, Stats, Recurring, Budgets,
Lending, Settings, and Account. Native iOS adds an Email tab (Gmail suggestions);
Android omits Email and uses four tabs (Home, Stats, Budgets, Lending) with
Recurring reached from Home. Responsive mobile web still surfaces Recurring as a
primary tab. Desktop web uses a sidebar. Web sheets/modals and native sheets are
transient state, not routes.

# Data architecture

- The application is local-first. Dexie is authoritative on web/Electron;
  GRDB is authoritative on iOS; Room is authoritative on Android. UI models are
  projections of observed local data, not the persistence contract.
- Local databases are account-scoped: `dimo-expenses:{WorkOS userId}` in
  IndexedDB, `dimo-{userId}.sqlite` on iOS, and `dimo-{userId}.db` on Android.
- Entity types are `category`, `paymentMethod`, `transaction`, `recurring`,
  `lend`, and singleton `preferences` (`id == "preferences"`). Workspace ID is
  currently the constant `"global"`.
- Persist money as positive integer minor units. Occurrence timestamps are Unix
  milliseconds; recurring anchors are local calendar strings (`YYYY-MM-DD`).
  Lending direction is `kind`: `lent` (user gave money), `repaid` (contact gave
  it back), `borrowed` (user took money), `returned` (user paid it back).
  `signedAmount` is positive for `lent`/`returned` and negative for
  `repaid`/`borrowed`, so a contact's net balance is positive when they owe the
  user and negative when the user owes them.
- Every entity write and its per-entity outbox operation must commit
  atomically. A later local edit replaces the pending operation for that key.
- Fresh databases seed only Cash (`payment-method-cash`) and default
  preferences with logical version zero. Pull before uploading defaults so a
  fresh client cannot overwrite existing cloud data.
- IDs are opaque strings. Relationships use `categoryId`, `paymentMethodId`,
  and `contactId`; display names are not keys. Deletes are versioned entity
  tombstones rather than local hard deletes.
- Preserve backwards decoding of optional legacy fields: category `emoji`,
  lend `contactId`/`kind`, and newer preference fields. Normalize old data in
  payload sanitizers, not ad hoc in screens.
- Cross-platform contract changes usually require coordinated edits in
  `app/data/model.ts`, repository/sanitizers, `convex/values.ts`,
  `convex/schema.ts`, `convex/sync.ts`,
  `ios-native/Dimo/Data/Model/Entities.swift`,
  `Data/PayloadSanitizer.swift`, `Sync/ConvexAPI.swift`, and the Android ports
  under `android-native/.../data/` and `sync/`.
- Swift and Kotlin values sent to Convex `v.number()` fields must be encoded as
  floating JSON numbers (`Double` / wire doubles); integer-typed encodings
  produce Convex `$integer` and fail validation.
- `preferences.defaultView` is currently normalized to `home`. The last-used
  payment method is device metadata and intentionally does not sync.

# Authentication and synchronization

- WorkOS authenticates every cloud call. Convex must derive ownership from
  `identity.tokenIdentifier`; never accept a client-provided owner/user ID.
- Web uses AuthKit with `ConvexProviderWithAuthKit`. iOS uses public-client
  PKCE via `ASWebAuthenticationSession`, stores its refresh token in Keychain,
  and uses the callback `dimo://callback`. Android uses the same public-client
  PKCE flow via Custom Tabs, stores its refresh token in
  EncryptedSharedPreferences / Keystore, and uses the same `dimo://callback`.
- The canonical sync cycle is: ensure workspace profile → pull all pages →
  enqueue untouched bootstrap defaults → push pending batches → pull again.
- Conflicts are last-write-wins by hybrid logical version
  `(timestamp, counter, deviceId)`. Observe remote versions before generating
  subsequent local versions.
- Accepted server writes increment a per-owner workspace revision. Deletes
  are permanent tombstones so long-offline clients cannot resurrect data.
- Normal sync is triggered by local writes, reconnect/focus/foreground, retry
  timers, and Convex revision subscriptions.
- Web “Sync now” hard-replaces only web-owned entity types and preserves
  native-owned `lend`. Native iOS “Sync now” is an ordinary sync; its separate
  explicit replacement action covers all types including `emailMessage`.
  Android “Sync now” is also ordinary sync; its full cloud replacement and
  `enqueueFullUpload` **exclude** `emailMessage` so iOS-owned email data is not
  wiped. Account deletion can clear every type. Hard replacement is destructive
  and is not normal sync.
- Client payload errors are permanent/blocked; auth, deployment, and network
  failures remain retryable. Preserve batch splitting that isolates one bad
  operation.
- Push batches are capped at 50. Pull and clear operations are paged. Preserve
  the durable revision cursor and the monotonic relationship between workspace
  revision notifications and entity revisions.
- Sign-out stops sync and deletes every local Dimo database before ending the
  WorkOS session. Account deletion must be online and clears all cloud types
  before performing the same local/session cleanup.

# Code ownership

| Path | Responsibility |
| --- | --- |
| `app/data/` | Web entity contract, Dexie schema, repository, sanitization, atomic outbox writes |
| `app/store/` | Web UI/navigation/form state and persistence orchestration |
| `app/sync/` | Web Convex coordinator, retries, merge and reset behavior |
| `app/features/` | UI-independent selectors, dates, stats, CSV, and feature tests |
| `app/components/common/`, `ui/`, `forms/` | Shared web UI |
| `app/components/web/`, `mobile/` | Surface-specific screens and shells |
| `convex/` | Authenticated schema, validators, ownership, revisions, pull/push/clear API |
| `electron/` | Desktop window, static export loading, and minimal preload bridge |
| `ios-native/Dimo/Data/` | GRDB schema, records, repository, entities, local outbox |
| `ios-native/Dimo/Domain/` | Native business calculations, formatting, dates, CSV |
| `ios-native/Dimo/Store/AppStore.swift` | Native UI state and mutation orchestration |
| `ios-native/Dimo/Sync/`, `Auth/` | Native Convex protocol/coordinator and WorkOS session |
| `ios-native/Dimo/Features/` | Native SwiftUI screens and forms |
| `android-native/app/.../data/` | Room schema, records, repository, entities, local outbox |
| `android-native/app/.../domain/` | Kotlin ports of native business calculations, formatting, dates, CSV |
| `android-native/app/.../store/` | Compose UI state and mutation orchestration (`AppStore`) |
| `android-native/app/.../sync/`, `auth/` | Convex protocol/coordinator and WorkOS PKCE session |
| `android-native/app/.../features/`, `design/` | Compose screens, sheets, and design tokens |
| `store/` | App Store listing and submission material |

TypeScript alias `@/*` resolves only to `app/*`. Put reusable business logic in
feature/domain selectors instead of views. Keep persistence models separate
from derived UI models.

# Shared domain rules

- Stats, overview totals, budget progress, and suggested budgets derive from
  real transactions. Keep calculations in `app/features/*/selectors.ts` and
  the corresponding `ios-native/Dimo/Domain/` and
  `android-native/.../domain/` ports.
- Categories have an emoji, optional monthly budget, tint, and sort order. A
  fresh account has no categories. Web category deletion also tombstones linked
  transactions and recurring bills; native currently tombstones linked
  transactions only. Keep each warning truthful and treat this as an explicit
  parity decision when changing deletion behavior.
- At least one payment method must remain active. Archiving the default must
  choose another active default. Existing records may continue displaying an
  archived method.
- Recurring bills are monthly or yearly. Use the local-date recurrence helpers
  so short months, leap years, and occurrence materialization stay consistent;
  do not replace calendar logic with fixed millisecond intervals.
- CSV import can create missing categories and transactions in one atomic local
  batch. Keep TypeScript, Swift, and Kotlin headers, amount/date parsing, export
  format, and category emoji fallback behavior compatible.
- Notification toggles are synced preferences only; there is currently no
  notification scheduling subsystem.

# Platform rules

## Lending

- Native iOS and Android are lending writers; web and Electron must remain
  read-only.
- Group people by address-book `contactId`, never display name. Legacy missing
  IDs fall back to the name. Contact names/IDs may sync; photos are read
  on-device and must never be persisted or synced.
- A settlement cannot overshoot the balance it closes: `repaid` is capped by
  what the contact owes, `returned` by what the user owes them. `lent` and
  `borrowed` open a balance and are uncapped. Use
  `LendSelectors.settlementLimit(for:contactId:in:excludingLendId:)` rather
  than re-deriving the cap, and when editing a settlement exclude that row from
  the available-balance calculation. Only contacts whose balance nets to zero
  are omitted from summaries — a negative balance means the user owes them and
  must still be listed.
- Editing an entry never flips its direction; the saved row's `kind` wins over
  the draft.
- iOS is currently the only client that can *record* a borrowing. Web reads all
  four directions correctly (`app/features/lending/selectors.ts`) but stays
  read-only, so it reports balances both ways without offering an entry form.
- Android still coerces an unrecognized `kind` to `lent`
  (`LendKind.fromWire`), so a borrowing displays there as a lend and inverts
  that contact's balance. Android only rewrites a row the user edits, so this
  is a display gap rather than data loss — port `LendKind`, `signedAmount`, and
  the `LendSelectors` balance/summary changes before adding borrowing UI there.
- The current unsettled cycle starts after the most recent zero balance. Use
  `LendSelectors.unsettledTransactions(for:in:)` rather than duplicating it.
- Native shared summaries use a plain-text share sheet
  (`UIActivityViewController` / Android `ACTION_SEND`), include only the
  current unsettled cycle, omit comments, show `+`/`-` amounts, and format
  dates as `dd-MMM-yyyy`.

## Native iOS

- `ios-native/project.yml` is the XcodeGen source of truth; generated
  `.xcodeproj`/workspaces are ignored. Regenerate after project or xcconfig
  changes.
- Runtime config flows from `Config/Debug.xcconfig` or `Release.xcconfig`
  through `Resources/Info.plist` to `AppConfig.swift`. Debug and Release
  currently target production; `Dev.xcconfig` contains development values.
- Never put WorkOS API keys or client secrets in iOS config. Convex URL and
  public WorkOS client ID are expected to be public.
- Native domain tests live in `ios-native/DimoTests/DomainTests.swift`.

## Native Android

- `android-native/` is a Gradle project (`compileSdk` / `targetSdk` 37,
  `minSdk` 26). Product flavors `prod` / `dev` mirror iOS xcconfig Convex URL
  and WorkOS client IDs into `BuildConfig` / `AppConfig`.
- Auth uses Custom Tabs + `dimo://callback` (same redirect as iOS) and stores
  the refresh token in EncryptedSharedPreferences. Never put WorkOS API keys
  or client secrets in Android config.
- Android excludes `emailMessage` from pull, push/full upload, and
  `clearWorkspace` so iOS-owned email suggestions survive Android full cloud
  replacement. Android does not implement the Email / Gmail / AI suggestions
  subsystem.
- Domain and repository unit tests live under
  `android-native/app/src/test/`. See `android-native/TESTING.md`.

## Web and design system

- `AppStoreProvider` in `app/store/app-store.tsx` observes Dexie, hydrates
  display models, starts sync, and exposes actions. Feature components should
  not query Convex or Dexie directly.
- Reuse `app/components/ui/`, `app/components/common/`, Tailwind theme tokens
  in `app/globals.css`, and `cn()` before introducing one-off primitives.
- Preserve both themes, safe-area/standalone-PWA behavior, keyboard handling,
  mobile tab swiping, focus states, accessibility labels, confirmations, and
  offline empty/error states when changing UI flows.
- Native visuals come from `ios-native/Dimo/DesignSystem/` and the iOS 26
  Liquid Glass tab shell. Keep the SwiftUI client idiomatic rather than
  mechanically copying React component structure.

# Configuration

- Web build-time variables: `NEXT_PUBLIC_CONVEX_URL`,
  `NEXT_PUBLIC_WORKOS_CLIENT_ID`, `NEXT_PUBLIC_WORKOS_REDIRECT_URI`.
- Convex deployment variable: `WORKOS_CLIENT_ID`; `WORKOS_API_KEY` is only for
  provisioning/configuration. Do not commit `.env*` or secret xcconfig files.
- `NEXT_PUBLIC_*` values are embedded at build time and frozen into Electron
  packages. Deploy/configure Convex before building clients against it.
- Although some docs describe cloud sync as optional, the current web
  `AuthRoot` requires valid WorkOS and Convex configuration and authentication.
- WorkOS profile name/email/photo are read-only in the product UI. Name/email
  are mirrored into preferences/workspace metadata because WorkOS JWT claims
  may omit them; the profile photo URL and address-book photos are never synced
  as Dimo entities.

# Commands and verification

```bash
npm ci
npm run dev                 # Next.js only
npm run convex:dev          # separate Convex watcher/codegen
npm run convex:export       # ZIP snapshot of the linked dev deployment → backups/
npm run convex:export:prod  # ZIP snapshot of production → backups/
npm run lint
npm run test:unit
npm test                    # unit tests followed by production static build
npm run electron:dev
npm run electron:preview
npm run electron:dist
```

Use `npm run lint && npm test` for normal web/backend validation. `npm test`
does not run lint, Electron tests, or iOS tests. Vitest uses the Node
environment with `fake-indexeddb`; tests are selector/repository/protocol
focused, with no browser E2E or Electron suite.

## Convex cloud backups

Convex table data (and optionally file storage) can be snapshotted without a
custom backup subsystem. Client local DBs (Dexie / GRDB) are separate and are
not included.

- **Dashboard:** Deployment → Backup & Restore → Backup Now (download the ZIP
  for long-term copies; Convex keeps manual backups ~7 days). Periodic daily
  or weekly backups require Convex Pro.
- **CLI / npm:** `npm run convex:export` (dev) or `npm run convex:export:prod`
  writes `backups/dimo-*-snapshot.zip` (gitignored). Equivalent raw CLI:
  `npx convex export --path …` / `npx convex export --prod --path …`.
- **Restore:** Dashboard Restore on a backup, or `npx convex import` of a
  downloaded ZIP. Restore replaces deployment table data; take a fresh backup
  first. Snapshots omit functions/schema (in git under `convex/`), env vars,
  and pending scheduled jobs.

See [Backup & Restore](https://docs.convex.dev/database/backup-restore) and
[CLI export](https://docs.convex.dev/cli/reference/export).

For behavior shared by web, iOS, and Android, add corresponding tests in each
language. For sync changes, cover fresh bootstrap, offline writes/reconnect,
conflicting versions, tombstone propagation, blocked payloads, full replacement
boundaries (including Android’s `emailMessage` exclusion), sign-out, and account
deletion as applicable.

For native setup and an arm64 simulator build:

```bash
cd ios-native
xcodegen generate
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
  xcodebuild -project Dimo.xcodeproj -scheme Dimo \
  -sdk iphonesimulator -destination "generic/platform=iOS Simulator" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build CODE_SIGNING_ALLOWED=NO
```

The native build requires full Xcode and an iOS 26 runtime. ConvexMobile lacks
an x86_64 simulator slice, so unconstrained simulator builds fail at link time.
Generic destinations can build but cannot execute tests; use an installed
named simulator or device UUID for `xcodebuild test`.

# Generated, ignored, and legacy files

- Never hand-edit `convex/_generated/*` or XcodeGen output. After Convex API or
  schema changes, run `npm run convex:dev` to regenerate bindings.
- `.next/`, `out/`, `release/`, `backups/`, coverage, Xcode projects,
  DerivedData, local databases, and `.env*` are generated/ignored.
- `npm run build` rewrites tracked `public/version.json`; account for that
  deliberate diff.
- `db/`, `drizzle/`, `worker/`, `drizzle.config.ts`, and `examples/d1/` are
  unused starter leftovers. Do not add D1/Drizzle dual writes.
- `design/` is historical prototype material, not runtime application code.
- `store/` is release copy, not runtime configuration; re-check its privacy and
  feature claims against current authentication, cloud sync, and analytics
  behavior before an App Store submission.
- Lint excludes Electron, iOS, and Android. There is currently no CI workflow or
  single command that validates all four clients.
