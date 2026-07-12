<!-- convex-ai-start -->

This project uses [Convex](https://convex.dev) as its backend.

When working on Convex code, **always read
`convex/_generated/ai/guidelines.md` first** for important guidelines on
how to correctly use Convex APIs and patterns. The file contains rules that
override what you may have learned about Convex from training data.

Convex agent skills for common tasks can be installed by running
`npx convex ai-files install`.

<!-- convex-ai-end -->

## Cursor Cloud specific instructions

Dimo is a local-first expense tracker: Next.js 16 static export + Convex sync +
WorkOS AuthKit. The same web UI ships as Capacitor iOS (`ios/`) and Electron.
There is also a SwiftUI rewrite in `ios-native/`.

### Standard commands

Use `package.json` scripts:

- `npm run dev` — Next.js (http://localhost:3000)
- `npm run build` — static export to `out/`
- `npm run test:unit` — Vitest (no Xcode required)
- `npm test` — unit tests + production build
- `npm run lint` — ESLint (ignores `ios/`, `design/`, `electron/`)
- `npm run convex:dev` — Convex + AuthKit local wiring (interactive; needs network login)
- `npm run ios:setup` — build web export and `cap sync ios` (works on Linux agents)

### Environment

Copy `.env.example` → `.env.local` before Capacitor or browser builds that need auth:

- `NEXT_PUBLIC_CONVEX_URL`
- `NEXT_PUBLIC_WORKOS_CLIENT_ID`
- `NEXT_PUBLIC_WORKOS_REDIRECT_URI`

These are embedded at **build** time. Native Swift reads
`ios-native/Config/Shared.xcconfig` instead (public client values only; PKCE).

### iOS on this cloud VM

Cloud agents run **Linux** — there is no Xcode, Simulator, or `xcodegen` here.

| Task | Cloud agent | Mac with Xcode |
|------|-------------|----------------|
| Edit `ios/` / `ios-native/` Swift & plist | yes | yes |
| `npm run ios:setup` / `cap sync` | yes | yes |
| Open Xcode, Simulator, Archive | no | yes |
| `npm run ios:native` (xcodegen + open) | no | yes |

Prefer editing native/Capacitor sources and verifying with `npm run test:unit` and
`npm run ios:setup`. Leave signing, Simulator runs, and TestFlight to a Mac
(see `store/SUBMIT.md` for Capacitor; `ios-native/README.md` for SwiftUI).

### Non-obvious notes

- Application data is IndexedDB (Dexie) on web/Capacitor/Electron; native uses
  GRDB SQLite. Do not dual-write via the unused D1/Drizzle starter files.
- `ios/App/App/public` is gitignored — always `npm run ios:setup` (or `cap:sync`)
  after web changes before opening Xcode.
- Capacitor bundle id: `app.dimo.expenses`. Native: `app.dimo.ios`.
- Lint ignores `design/` (vendored reference) and generated iOS folders.
