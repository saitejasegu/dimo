# AGENTS.md

## Project overview

This is a single **Next.js 16 / React 19 / Tailwind CSS 4** app
(`dimo-expenses-ui`) — a client-side "Dimo" personal expense-tracking dashboard.
There is no backend, database, or external service to run; the app uses
in-memory seed data (`app/data/seed.ts`) and resets on page reload.

The app renders two layouts from one shared store:
- **mobile** (`app/components/mobile/`) — phone frame, bottom tab bar, bottom sheets.
- **web** (`app/components/web/`) — window chrome, sidebar, centered modals.

`app/page.tsx` selects between them at runtime via `useIsMobile()` (900px
breakpoint). Both build to match the static mockups in `design/`
(`mobile.dc.html`, `web.dc.html`).

## Commands

Use the `package.json` scripts:
- `npm run dev` — dev server (http://localhost:3000, Turbopack).
- `npm run build` — production build (also what `npm test` runs).
- `npm run lint` — ESLint. Clean on a fresh checkout; the `design/` mockups are
  ignored via `--ignore-pattern design`.

## Code layout & conventions

All application code lives under `app/`. The `@/*` TypeScript alias maps to
`./app/*`, so imports look like `@/lib/...`, `@/features/...`, `@/store/...`,
`@/components/...`. Keep this convention.

Layered architecture (respect the direction of dependencies):
- `app/lib/` — domain types, formatting, `cn`. No React, no store.
- `app/data/seed.ts` — the ONLY source of initial data; the backend swap-in point.
- `app/features/<feature>/selectors.ts` — pure, testable functions over state.
- `app/features/<feature>/hooks.ts` — thin memoized adapters over the store.
- `app/store/` — one reducer-based store (`state.ts`, `actions.ts`,
  `reducer.ts`, `app-store.tsx`). All mutations and save/validation logic live
  in the reducer. Components mutate only through `useAppActions()`.
- `app/components/{ui,common,forms}` — reusable/presentational; `{mobile,web}` —
  platform-specific compositions.

Guidelines when editing:
- No "god components" — keep components small and composed. Shared logic belongs
  in selectors/hooks, not duplicated across mobile and web.
- Components should be presentational: read via `useAppState()` /
  feature hooks, write via `useAppActions()`. Don't compute domain logic inline.
- Styling uses Tailwind theme tokens defined in `app/globals.css` (e.g. brand
  colors, fonts, animations) — prefer those tokens over hard-coded values.

## Non-obvious notes

- The repo root still contains leftover starter-template files that are **not**
  part of the Next.js build and require no setup: `worker/`, `db/`, `drizzle/`,
  `drizzle.config.ts`, `examples/`. `tsconfig.json` excludes them. (`vite.config.ts`
  and the vite plugin have been removed — this app does not use vite/vinext.)
- `npm test` maps to `npm run build`; it does NOT run `tests/rendered-html.test.mjs`,
  which is stale and not wired into any script.
- `design/` and its `support.js` are vendored design-reference artifacts, not app
  code; they are excluded from lint and the build.

## Smoke test

Load http://localhost:3000/ and:
1. Switch tabs / sidebar entries (Home·Overview, Activity, Stats, Recurring, Budgets).
2. Open "Add expense", enter a numeric amount (Save stays disabled until the
   amount is valid), pick a category, save, and confirm the new transaction and
   the updated "Spent in July" total.
3. On Recurring, toggle a bill to pause/resume it (a toast confirms).
4. Resize across the 900px breakpoint to confirm the mobile/web swap.
