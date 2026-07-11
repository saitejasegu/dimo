# Dimo — Expenses

Dimo is a local-first personal spending tracker built with Next.js 16 and React 19. The same application ships as a browser app, an Electron desktop app, and a Capacitor iOS app.

## Data architecture

IndexedDB is the application database on every platform. Dexie provides typed tables and reactive queries. Transactions, recurring expenses, categories, payment methods, and preferences are read locally, so the app starts quickly and remains fully usable offline.

Every local entity write and its outbox operation commit in one IndexedDB transaction. When a Convex deployment is configured, the sync coordinator:

1. Pulls cloud changes after its durable revision cursor.
2. Merges them using hybrid logical versions.
3. Pushes pending operations in idempotent batches.
4. Pulls once more to confirm canonical cloud state.

Synchronization runs while the app is open after local writes, reconnects, window focus, visibility changes, and Convex revision notifications. Account contains detailed status and a manual **Sync now** action that clears the cloud workspace and re-uploads the full local snapshot.

WorkOS AuthKit authenticates every cloud sync call. Convex derives ownership from the verified token rather than a client-provided user ID, and each WorkOS user has an isolated revision stream. Local IndexedDB databases are also separated by WorkOS user ID, preventing account switches on a shared device from exposing another user's local transactions.

The empty D1/Drizzle files in this starter are not connected to application data and must not be used for dual writes.

## Prerequisites

- Node.js `>=22.13.0`
- A Convex account for cloud synchronization
- A WorkOS AuthKit environment with Google and Apple social login enabled

## Local development

```bash
npm install
npm run dev
```

To link a Convex development project and provision a Convex-managed WorkOS environment:

```bash
npm run convex:dev
```

The first run is interactive. It creates/selects the Convex project, offers to provision a managed WorkOS team, deploys the JWT configuration, and writes the ignored `.env.local` values used by the app. Keep it running beside `npm run dev` while changing backend functions.

For an existing WorkOS team, configure the deployment first:

```bash
npx convex env set WORKOS_CLIENT_ID client_...
npx convex env set WORKOS_API_KEY sk_test_...
```

Then add these browser-safe values to `.env.local`:

```bash
NEXT_PUBLIC_WORKOS_CLIENT_ID=client_...
NEXT_PUBLIC_WORKOS_REDIRECT_URI=http://localhost:3000/callback
```

In the WorkOS dashboard, enable only Google and Apple under Authentication → Social Login, disable the other authentication methods, and add `http://localhost:3000/callback` as an allowed redirect. Google and Apple must both be configured there before their buttons can complete sign-in.

For a production deployment:

```bash
npm run convex:deploy
NEXT_PUBLIC_CONVEX_URL=https://YOUR_DEPLOYMENT.convex.cloud npm run build
```

`NEXT_PUBLIC_CONVEX_URL`, `NEXT_PUBLIC_WORKOS_CLIENT_ID`, and `NEXT_PUBLIC_WORKOS_REDIRECT_URI` are embedded at build time. Set the production values before browser hosting, Electron packaging, or Capacitor synchronization.

## Scripts

- `npm run dev` — Next.js development server.
- `npm run build` — static production export to `out/`.
- `npm test` — unit/Convex protocol tests followed by the production build.
- `npm run test:unit` — Vitest suite only.
- `npm run test:watch` — Vitest watch mode.
- `npm run lint` — ESLint.
- `npm run convex:dev` — link/run the Convex development deployment and regenerate bindings.
- `npm run convex:deploy` — deploy the Convex schema and functions.
- `npm run ios` — build, sync, and open the Capacitor iOS project.
- `npm run electron:dev` — run Next.js and Electron together.
- `npm run electron:preview` — open the static export in Electron.
- `npm run electron:dist` — package desktop installers.

## Fresh-install behavior

A fresh local database contains standard Dining, Groceries, Bills, Transit, and Shopping categories, Cash as the default payment method, and default preferences. It contains no sample transactions or recurring expenses.

For development, clear the `dimo-expenses` IndexedDB database in browser developer tools to simulate a fresh installation. Reloading normally preserves all local records and pending sync work.

## Sync troubleshooting

- **Authentication setup required:** one of the public Convex or WorkOS build variables is missing.
- **Offline:** local writes continue and will upload after connectivity returns.
- **Pending:** operations are safely stored in IndexedDB but not yet acknowledged.
- **Error:** open Account for the transport error and retry with **Sync now** (full cloud replace from this device).
- If the schema or generated bindings changed, run `npm run convex:dev` again.

Tombstones are intentionally retained indefinitely so a device that has been offline for a long time cannot resurrect deleted data.

## Platform notes

Electron and Capacitor both bundle the static `out/` export. Background sync means asynchronous synchronization while the app process is open; suspended iOS background execution is not included. WorkOS recommends separate application records for web, desktop, and mobile surfaces so each can use a platform-appropriate client ID, redirect URI, and session policy.

The Convex folder contains strict payload validators, authenticated owner-scoped indexes, revision-indexed pull queries, and an idempotent last-write-wins push mutation.
