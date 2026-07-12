# Dimo

Personal spending tracker — expenses, budgets, recurring bills, and stats. Local-first on every platform, with optional cloud sync through Convex and WorkOS AuthKit.

| Surface | Stack | Notes |
| --- | --- | --- |
| Web | Next.js 16, React 19, Dexie / IndexedDB | Static export to `out/` |
| Desktop | Electron wrapping the same export | `electron/` |
| iOS | SwiftUI + GRDB SQLite | `app.dimo.ios` · `ios-native/` |

Web, desktop, and native iOS share the same Convex backend and WorkOS account. Lending is native-iOS-only today; other entity types sync across clients.

## Features

- Log expenses with categories (emoji + optional monthly budget) and payment methods
- Budgets overview and category management
- Recurring monthly / yearly bills
- Activity list, stats ranges, and CSV export
- Account sync status, sign-in (Google / Apple via WorkOS), and preferences
- **Native iOS:** lending tracker, Liquid Glass tab UI (requires iOS 26+)

## Architecture

### Local-first data

| Client | Store |
| --- | --- |
| Web / Electron | IndexedDB via Dexie (`dimo-expenses`, scoped per WorkOS user) |
| Native iOS | SQLite via GRDB (`dimo-{userId}.sqlite`) |

Entity types: `category`, `paymentMethod`, `transaction`, `recurring`, `preferences`, and `lend` (native). Every local write and its outbox op commit together. The app works fully offline; sync runs when a Convex deployment and auth are configured.

### Sync

When Convex is linked, the sync coordinator:

1. Pulls cloud changes after its durable revision cursor
2. Merges with hybrid logical versions (last-write-wins)
3. Pushes pending outbox ops in idempotent batches
4. Pulls once more to confirm canonical state

Triggers include local writes, reconnect, focus / visibility, and Convex revision notifications. Account → **Sync now** clears this app’s owned cloud entity types and re-uploads the local snapshot (web leaves native-only types like `lend` alone unless you wipe the full account).

WorkOS AuthKit authenticates every cloud call. Convex derives ownership from the verified token; each user has an isolated revision stream and a separate local database.

The empty D1 / Drizzle / worker stubs under `db/`, `drizzle/`, and `worker/` are unused starter leftovers — do not dual-write to them.

### Repo layout

```
app/           Next.js UI, features, IndexedDB data layer, sync coordinator
convex/        Schema, sync pull/push, WorkOS JWT config
electron/      Desktop shell
ios-native/    SwiftUI iOS app (see ios-native/README.md)
store/         App Store listing copy and submission notes
public/        Static assets
```

## Prerequisites

- Node.js `>=22.13.0`
- Convex account (cloud sync)
- WorkOS AuthKit with Google and Apple social login
- For native iOS: Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen), iOS 26 SDK

## Local development (web)

```bash
npm install
npm run dev
```

Link Convex and provision a managed WorkOS environment:

```bash
npm run convex:dev
```

Keep that process running beside `npm run dev` while changing backend functions. The first run is interactive and writes ignored `.env.local` values.

### Existing WorkOS team

```bash
npx convex env set WORKOS_CLIENT_ID client_...
npx convex env set WORKOS_API_KEY sk_test_...
```

Add to `.env.local`:

```bash
NEXT_PUBLIC_WORKOS_CLIENT_ID=client_...
NEXT_PUBLIC_WORKOS_REDIRECT_URI=http://localhost:3000/callback
```

In the WorkOS dashboard: enable only Google and Apple under Authentication → Social Login, and allow `http://localhost:3000/callback`.

### Production web build

```bash
npm run convex:deploy
NEXT_PUBLIC_CONVEX_URL=https://YOUR_DEPLOYMENT.convex.cloud npm run build
```

`NEXT_PUBLIC_CONVEX_URL`, `NEXT_PUBLIC_WORKOS_CLIENT_ID`, and `NEXT_PUBLIC_WORKOS_REDIRECT_URI` are embedded at build time — set them before hosting or Electron packaging.

## Scripts

| Script | Purpose |
| --- | --- |
| `npm run dev` | Next.js dev server |
| `npm run build` | Static export → `out/` |
| `npm test` | Unit tests + production build |
| `npm run test:unit` | Vitest only |
| `npm run lint` | ESLint |
| `npm run convex:dev` | Convex dev deployment + codegen |
| `npm run convex:deploy` | Deploy Convex schema/functions |
| `npm run electron:dev` | Next.js + Electron |
| `npm run electron:preview` | Electron on static export |
| `npm run electron:dist` | Package desktop installers |

## Native iOS (`ios-native/`)

SwiftUI client sharing Convex + WorkOS. Full setup: [ios-native/README.md](ios-native/README.md).

```bash
brew install xcodegen
cd ios-native
xcodegen generate
open Dimo.xcodeproj
```

Config: `Config/Debug.xcconfig` / `Release.xcconfig` → Info.plist (`ConvexURL`, `WorkOSClientID`). Register `dimo://callback` on the WorkOS client (public client + PKCE).

App Store listing copy and submission steps: [store/SUBMIT.md](store/SUBMIT.md), `store/listing.json`.

## Fresh install

A new local database seeds Dining, Groceries, Bills, Transit, and Shopping categories, Cash as the default payment method, and default preferences — no sample transactions or recurring rows.

Clear the `dimo-expenses` IndexedDB database in browser tools to simulate a fresh install. Reloading preserves local records and pending sync work.

## Sync troubleshooting

- **Authentication setup required** — a public Convex or WorkOS build variable is missing
- **Offline** — local writes queue and upload when connectivity returns
- **Pending** — ops are in the outbox, not yet acknowledged
- **Error** — open Account for the transport error; retry with **Sync now**
- After schema / binding changes, run `npm run convex:dev` again

Tombstones are retained indefinitely so a long-offline device cannot resurrect deleted data.

## Platform notes

Electron ships the static `out/` export. Sync runs while the process is open; suspended iOS background execution is not included. Prefer separate WorkOS application records per surface (web, desktop, mobile) so each can use the right client ID, redirect URI, and session policy.
