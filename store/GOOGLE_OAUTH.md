# Google OAuth brand verification — Dimo

Status as of Aug 8, 2026: the domain and pages are done. The two open items are
both **Branding guidelines** failures from the Aug 7, 2026 review, and both are
fixed by re-uploading assets and correcting console fields — no new hosting work.

## The two failures and what fixes them

### 1. "The app name shown on your OAuth consent screen does not match the app name on your home page"

The homepage brands itself as exactly **Dimo** — `<h1>Dimo</h1>`, plus an
explicit `Application name: Dimo` line, in server-rendered HTML.

So the mismatch is the **console field**, not the site. In Google Cloud →
APIs & Services → OAuth consent screen → Branding:

- **App name** must be exactly `Dimo`

Not `Dimo — Personal expense tracker`, not `Dimo App`, not the Cloud project
name (`dimo-ios`, `My First Project`, etc.). Google compares this string against
the name on the homepage literally, so any suffix fails the check.

Keep `<h1>Dimo</h1>` in `app/components/marketing/PublicHome.tsx` as the bare
app name. The `<title>` may stay descriptive; the visible H1 is what must match.

### 2. "Your logo does not uniquely identify your brand and identity"

The old logo was a bare letter **D** monogram. A plain letterform reads as
generic to reviewers, which is what this rejection means.

Replaced with a distinct symbol mark: a **torn paper receipt** holding three
ledger rows. Source of truth is `public/brand/dimo-logo.svg`; every raster icon
is regenerated from it with:

```sh
node scripts/render-icons.mjs
```

**You must re-upload the logo** — the console keeps the old image until you
replace it:

- Upload file: `store/oauth-logo.png` (120×120, required size)
- The same artwork is served on the homepage at `/brand/dimo-logo-512.png`,
  in the header and footer, so the site logo and consent-screen logo match.

## Console fields to set

In Google Cloud → OAuth consent screen → Branding:

| Field | Value |
| --- | --- |
| App name | `Dimo` |
| App logo | upload `store/oauth-logo.png` |
| Application home page | `https://dimoapp.xyz` |
| Privacy policy link | `https://dimoapp.xyz/privacy` |
| Terms of service link | `https://dimoapp.xyz/terms` |
| Authorized domain | `dimoapp.xyz` |

**Use the bare apex `https://dimoapp.xyz`.** The previous config pointed at
`https://dimoapp.xyz/about/`, which **308-redirects** to `/about`; branding
crawls fail on redirecting homepages. The apex now returns 200 with the full
server-rendered public page, so `/about` is no longer needed as the homepage
(it stays published as a plain-HTML fallback).

Verify before resubmitting:

```sh
curl -sI https://dimoapp.xyz | head -1     # expect: HTTP/2 200 (not 308)
curl -s  https://dimoapp.xyz | grep -o '<h1[^>]*>[^<]*</h1>'   # expect: Dimo
```

Then: **I have fixed the issues** → Proceed.

## Homepage content checklist (already satisfied)

`/` is server-rendered public HTML — not behind auth, not client-only.

| Google requirement | On the Dimo homepage |
| --- | --- |
| Identify the app/brand | H1 `Dimo`, logo in header and footer |
| Describe functionality | "What Dimo does" feature list |
| Explain why user data is requested | "Why Dimo requests Google user data" (sign-in + optional `gmail.readonly`) |
| Privacy policy link matching consent screen | `/privacy` on the same domain |
| Visible without login | Content is in the initial HTML response |
| Not only a login wall | Marketing and purpose copy surround the sign-in buttons |

## Notes

- `dimo-silk.vercel.app` is fine for development, but never as an OAuth
  homepage or authorized domain — the top private domain there is `vercel.app`,
  which you do not own, so ownership checks fail regardless of page content.
- Both `dimoapp.xyz` and `www.dimoapp.xyz` currently return 200. Keep every
  console URL on the apex so the crawler never crosses hosts.
- The Google account that owns the Cloud project must be a Search Console
  **Owner** of the `dimoapp.xyz` property.
