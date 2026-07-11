# Dimo — Expenses

A client-side personal spending tracker built with **Next.js 16**, **React 19**,
and **Tailwind CSS 4**. It renders two distinct, pixel-faithful experiences from
a single shared state layer:

- a **mobile** app (phone frame, bottom tab bar, bottom sheets) — Capacitor iOS
- a **web** app (window chrome, sidebar navigation, centered modals) — browser + Electron

The UI is data-driven from in-memory seed data. There is no backend yet — the
architecture is intentionally structured so a real backend can be dropped in by
replacing the data/selector layers without touching components.

## Prerequisites

- Node.js `>=22.13.0`

## Quick Start

```bash
npm install
npm run dev      # http://localhost:3000
```

## Scripts

- `npm run dev` — start the dev server (Turbopack).
- `npm run build` — static production export to `out/` (also what `npm test` runs).
- `npm run start` — serve the `out/` folder locally.
- `npm run lint` — ESLint (the reference `design/` mockups are ignored).
- `npm run ios` — build, sync Capacitor, open the Xcode iOS project.
- `npm run cap:sync` — build + sync web assets into `ios/` without opening Xcode.
- `npm run electron:dev` — Next.js + Electron together (desktop shell against the dev server).
- `npm run electron:preview` — build the static export, then open it in Electron.
- `npm run electron:pack` — build an unpackaged app under `release/` (for smoke-testing).
- `npm run electron:dist` — build installers (macOS `.dmg`, Windows NSIS, Linux AppImage).

## Desktop (Electron)

Electron hosts the **web** UI in a desktop window (`electron/`, app ID `app.dimo.expenses`).

```bash
npm run electron:dev      # develop against localhost:3000
npm run electron:preview # production static export in Electron
npm run electron:dist    # package installers into release/
```

## iOS / App Store

The mobile UI ships inside a Capacitor iOS shell (`ios/`, bundle ID `app.dimo.expenses`).

1. Install full **Xcode** (not only Command Line Tools) and join the Apple Developer Program.
2. Run `npm run ios`, set your signing team, then Run / Archive.
3. Follow `store/SUBMIT.md` for TestFlight, listing copy, screenshots, and review submission.
4. Host the static `out/` site so App Store Connect can use `https://YOUR_DOMAIN/privacy`.

Store listing draft: `store/listing.json`. App icon: `store/AppIcon-1024.png`.

## Architecture

All application code lives under `app/`. The import alias `@/*` maps to
`./app/*` (see `tsconfig.json`), so modules import each other as `@/lib/...`,
`@/features/...`, `@/store/...`, `@/components/...`.

```
app/
  layout.tsx            # root layout + fonts (Space Grotesk, IBM Plex Sans)
  globals.css           # Tailwind theme tokens (colors, fonts, animations)
  page.tsx              # responsive entry: picks MobileApp vs WebApp

  lib/                  # framework-agnostic primitives
    types.ts            # domain types (Transaction, Recurring, ...)
    format.ts           # money / percent / compact formatting
    cn.ts               # className helper

  data/
    seed.ts             # initial mock data — the backend swap-in point

  features/             # domain logic, grouped by feature
    transactions/       # selectors (filter/search/group) + hook
    recurring/          # selectors (active total, upcoming) + hook
    budgets/            # selectors (per-category, totals, top) + hook
    stats/              # constants + selectors (scope, bars, merchants) + hook
    overview/           # composed hook for the home/overview screen
    account/            # settings option definitions

  store/                # single reducer-based store (UI + data state)
    state.ts            # AppState shape + initial state
    actions.ts          # typed action union
    reducer.ts          # pure reducer (all mutations + save/validation logic)
    app-store.tsx       # provider, bound action creators, toast lifecycle

  hooks/
    useIsMobile.ts      # viewport breakpoint (900px) with hydration guard

  components/
    ui/                 # reusable primitives (Button, Card, Chip, Sheet, Modal, ...)
    common/             # shared composites (TransactionRow, CategoryBar, MonthBars, ...)
    forms/              # shared form bodies reused by mobile sheets + web modals
    mobile/             # phone frame, tab bar, FAB, screens, bottom sheets
    web/                # window chrome, sidebar, screens, modals
```

### Data flow

1. **`data/seed.ts`** provides the initial state.
2. **`store/`** holds all state and exposes typed actions via
   `useAppState()` / `useAppActions()`.
3. **`features/*/selectors.ts`** are pure functions that derive view data from
   state; **`features/*/hooks.ts`** are thin, memoized adapters over the store.
4. **`components/`** are presentational and consume hooks + actions only.

### Mobile vs web

`page.tsx` wraps the tree in `AppStoreProvider` and swaps between `MobileApp`
and `WebApp` based on `useIsMobile()` (900px breakpoint). Both platforms read
the same store and reuse `components/ui`, `components/common`, and
`components/forms`; only the layout compositions differ (bottom sheets on
mobile, modals on web).

## Design reference

The `design/` folder contains the original static HTML mockups
(`mobile.dc.html`, `web.dc.html`) the UI is built to match. These are reference
artifacts only and are excluded from lint and the build.

## Adding a backend

Because components depend only on domain types and store hooks, integrating a
backend is localized:

1. Replace the constants in `app/data/seed.ts` with data fetched from your API.
2. Feed that data into the store (or replace the reducer's data slices with
   server state) — the domain types in `app/lib/types.ts` are the contract.
3. Selectors, hooks, and components remain unchanged.
