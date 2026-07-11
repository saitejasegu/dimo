# Dimo — Expenses

Dimo is a local-first personal spending tracker built with Next.js 16 and React 19. The same application ships as a browser app, an Electron desktop app, and a Capacitor iOS app.

## Data architecture

IndexedDB is the application database on every platform. Dexie provides typed tables and reactive queries. Transactions, recurring expenses, categories, payment methods, and preferences are read locally, so the app starts quickly and remains fully usable offline.

Every local entity write and its outbox operation commit in one IndexedDB transaction. When a Convex deployment is configured, the sync coordinator:

1. Pulls cloud changes after its durable revision cursor.
2. Merges them using hybrid logical versions.
3. Pushes pending operations in idempotent batches.
4. Pulls once more to confirm canonical cloud state.

Synchronization runs while the app is open after local writes, reconnects, window focus, visibility changes, and Convex revision notifications. Account contains detailed status and a manual **Sync now** action.

> **Security warning:** authentication and authorization are deliberately not implemented yet. Every client configured with the deployment URL reads and writes the single `global` workspace. Do not expose this deployment to untrusted users or use it for sensitive production data.

The empty D1/Drizzle files in this starter are not connected to application data and must not be used for dual writes.

## Prerequisites

- Node.js `>=22.13.0`
- A Convex account for cloud synchronization

## Local development

```bash
npm install
npm run dev
```

Without a Convex URL, Dimo runs in **Local only** mode and all features except cloud replication work normally.

To link a new Convex development project:

```bash
npm run convex:dev
```

The interactive command creates/selects the project, generates deployment-specific bindings, and writes the ignored `.env.local` containing `CONVEX_DEPLOYMENT` and `NEXT_PUBLIC_CONVEX_URL`. Keep it running beside `npm run dev` while changing backend functions.

For a production deployment:

```bash
npm run convex:deploy
NEXT_PUBLIC_CONVEX_URL=https://YOUR_DEPLOYMENT.convex.cloud npm run build
```

`NEXT_PUBLIC_CONVEX_URL` is embedded at build time. Set it before browser hosting, Electron packaging, or Capacitor synchronization.

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

- **Local only:** `NEXT_PUBLIC_CONVEX_URL` was not present at build time.
- **Offline:** local writes continue and will upload after connectivity returns.
- **Pending:** operations are safely stored in IndexedDB but not yet acknowledged.
- **Error:** open Account for the transport error and retry with **Sync now**.
- If the schema or generated bindings changed, run `npm run convex:dev` again.

Tombstones are intentionally retained indefinitely so a device that has been offline for a long time cannot resurrect deleted data.

## Platform notes

Electron and Capacitor both bundle the static `out/` export. Background sync means asynchronous synchronization while the app process is open; suspended iOS background execution is not included.

The Convex folder contains strict payload validators, revision-indexed pull queries, and an idempotent last-write-wins push mutation. A future authentication phase can replace the constant workspace with an authenticated workspace ID without changing the local outbox or revision protocol.
