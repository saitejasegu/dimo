# AGENTS.md

## Cursor Cloud specific instructions

This is a single **Next.js 16** app (`dimo-expenses-ui`) — a client-side "Dimo" personal
expense-tracking dashboard. All application code lives in `app/` (`page.tsx`, `layout.tsx`,
`globals.css`, `chatgpt-auth.ts`). There is no backend, database, or external service to run;
the dashboard uses in-memory mock data and resets on page reload.

Standard commands are defined in `package.json` `scripts` — use those:
- `npm run dev` — start the dev server (http://localhost:3000). Started via Turbopack.
- `npm run build` — production build (also what `npm test` runs).
- `npm run lint` — ESLint.

Non-obvious notes:
- The repo root contains leftover starter-template files that are **not** part of the
  Next.js build and require no setup: `vite.config.ts`, `worker/`, `build/`, `db/`,
  `drizzle/`, `drizzle.config.ts`, `examples/`. `tsconfig.json` excludes most of them, and
  `package.json` does not depend on `vinext`/`vite`/`drizzle-kit`. The README describes the
  original `vinext` starter, not this app — trust `package.json` scripts instead.
- `npm test` maps to `npm run build`; it does NOT run `tests/rendered-html.test.mjs`. That
  `.mjs` test is stale (references a nonexistent `dist/server/index.js` and `_sites-preview/`
  and asserts a different title) and will fail if run directly — it is not wired into any script.
- `npm run lint` reports 2 pre-existing errors + warnings in `design/support.js` (a vendored
  design-reference artifact, not app code). These are unrelated to the app in `app/` and exist
  on a clean checkout; do not treat them as regressions introduced by your changes.
- To smoke-test the app: load http://localhost:3000/, click "+ Add expense", enter a numeric
  amount (the "Save expense" button stays disabled until the amount field holds a valid number),
  fill merchant/category, save, and confirm the new transaction and updated "Spent in July" total.
