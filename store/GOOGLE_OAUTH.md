# Google OAuth brand verification — Dimo

Status as of the Aug 8, 2026 review:

- Domain, homepage, privacy, and terms — **done**.
- Logo ("does not uniquely identify your brand") — **cleared.** The letter-D
  monogram was replaced with the torn-receipt mark and re-uploaded; this item
  disappeared from the Aug 8 review.
- App name mismatch — **still open**, and the cause is not what it looks like.
  See below.

## The open failure

### 1. "The app name shown on your OAuth consent screen does not match the app name on your home page"

**This is not a console field and not a homepage problem.** Both sides already
say `Dimo`: the Branding page's App name is `Dimo`, and the homepage ships
`<h1>Dimo</h1>` plus an `Application name: Dimo` line in server-rendered HTML,
byte-identical on the apex and `www` hosts.

The real cause is that **web sign-in does not use our own Google OAuth client.**
`SignInButtons` calls WorkOS AuthKit, and the WorkOS environment is configured
with *WorkOS's* default Google credentials. So the consent screen a reviewer
actually reaches from the homepage is branded **workos.com**, not **Dimo** —
which is exactly the mismatch being reported. Editing the Branding page cannot
fix it, because that page describes a different OAuth client than the one the
sign-in button reaches.

**Fix — bring your own Google credentials into WorkOS:**

1. Google Cloud → APIs & Services → **Credentials** → Create credentials →
   **OAuth client ID** → *Web application*. Create it in the **same project**
   whose consent screen is branded `Dimo`.
2. Add the authorized redirect URI that the WorkOS dashboard shows for Google
   OAuth (WorkOS displays the exact callback to paste; it is a
   `api.workos.com` URL, not a `dimoapp.xyz` one).
3. WorkOS Dashboard → **Authentication → Google OAuth** → switch from WorkOS's
   default credentials to **your own**, pasting that client ID and secret.
4. Re-run sign-in. The Google screen must now read **"Sign in to continue to
   Dimo"** with the Dimo receipt logo, not workos.com.

Only after step 4 does the consent screen match the homepage.

### 1b. Web sign-in is currently broken on the live domain

Separately, and worth fixing before the next review since **App functionality**
is still an unreviewed section: the deployed site derives its redirect URI from
`window.location.origin`, so it asks WorkOS for `https://www.dimoapp.xyz/callback`.
WorkOS rejects it:

```
https://api.workos.com/user_management/authorize?...&redirect_uri=https://www.dimoapp.xyz/callback
  -> stable-river-76-staging.authkit.app/redirect-uri-invalid
```

Both the apex and `www` callbacks are rejected; only `http://localhost:3000/callback`
is registered. A reviewer clicking "Sign in with Google" lands on a WorkOS error
page. Also note `stable-river-76-staging` — the live site is pointed at a WorkOS
**staging** environment.

**Fix:** in the WorkOS **Production** environment, register redirect URIs
`https://dimoapp.xyz/callback` and `https://www.dimoapp.xyz/callback`, then set
the production `NEXT_PUBLIC_WORKOS_CLIENT_ID` in Vercel to that environment's
client ID. Do the "bring your own Google credentials" step above in that same
production environment.

## Resolved: "Your logo does not uniquely identify your brand and identity"

Kept for the record, and because the icon pipeline below is still how you
regenerate brand assets.

The old logo was a bare letter **D** monogram. A plain letterform reads as
generic to reviewers, which is what that rejection meant.

Replaced with a distinct symbol mark: a **torn paper receipt** holding three
ledger rows. Source of truth is `public/brand/dimo-logo.svg`; every raster icon
is regenerated from it with:

```sh
node scripts/render-icons.mjs
```

The console keeps the old image until you replace it, so a logo change always
needs a manual re-upload:

- Upload file: `store/oauth-logo.png` (120×120, required size)
- The same artwork is served on the homepage at `/brand/dimo-logo-512.png`,
  in the header and footer, so the site logo and consent-screen logo match.

## Console fields — already correct, leave them alone

Verified in the Branding page on Aug 8, 2026:

| Field | Value | State |
| --- | --- | --- |
| App name | `Dimo` | correct |
| App logo | receipt mark | correct, re-uploaded |
| Application home page | `https://www.dimoapp.xyz/` | fine — returns 200, no redirect |
| Privacy policy link | `https://www.dimoapp.xyz/privacy` | fine |

`www` and the apex serve byte-identical HTML, so either host passes. Do **not**
go back to `https://dimoapp.xyz/about/` — that path 308-redirects to `/about`,
and branding crawls fail on redirecting homepages.

Verify the page a reviewer sees:

```sh
curl -sI https://www.dimoapp.xyz/ | head -1                        # HTTP/2 200
curl -s  https://www.dimoapp.xyz/ | grep -o '<h1[^>]*>[^<]*</h1>'  # Dimo
```

Resubmit with **I have fixed the issues** → Proceed only *after* the WorkOS
credential swap above, since that is the actual blocker.

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
