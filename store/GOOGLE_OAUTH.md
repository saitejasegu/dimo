# Google OAuth homepage + brand verification — Dimo

## Critical: you need a domain you own

Google’s homepage rules require the site to be hosted on a **verified domain you
own**. A `*.vercel.app` URL does **not** qualify for ownership the way a custom
domain does:

- Homepage today: `https://dimo-silk.vercel.app`
- Top private domain of that host is `vercel.app` (owned by Vercel, not you)

That is why Cloud keeps saying: *“The website of your home page URL is not
registered to you.”* Search Console HTML-tag checks on a Vercel subdomain are
not enough for OAuth brand verification.

### What to do

1. **Buy a domain** you control (examples: `dimo.app`, `getdimo.com`, `dimo.finance`).
2. In **Vercel** → Project → Settings → Domains → add that domain and finish DNS.
3. Redeploy so these URLs work on your domain:
   - `https://YOURDOMAIN/`
   - `https://YOURDOMAIN/privacy`
   - `https://YOURDOMAIN/terms`
4. In **Google Search Console**, add a **Domain** property for `YOURDOMAIN`
   (DNS TXT verification — preferred) or URL prefix `https://YOURDOMAIN`.
5. Use the **same Google account** that owns the Cloud OAuth project; that
   account must be a Search Console **Owner**.
6. In Google Cloud → OAuth Branding / Authorized domains:
   - Authorized domain: `YOURDOMAIN` (not `vercel.app`)
   - Home page: `https://YOURDOMAIN`
   - Privacy: `https://YOURDOMAIN/privacy`
   - Terms: `https://YOURDOMAIN/terms`
7. Update App Store listing URLs in `store/listing.json` to the same domain.
8. Re-submit branding verification.

Until the homepage/privacy URLs use **your** domain, Google will keep failing
ownership no matter how complete the page content is.

## Fix apex ↔ www redirect (common branding fail)

Right now `https://dimoapp.xyz` **308-redirects** to `https://www.dimoapp.xyz`.
Google’s branding crawler often fails purpose/name checks on redirecting
homepages.

**Pick one canonical URL and use it everywhere:**

### Recommended: apex primary
1. Vercel → Project → Settings → **Domains**
2. Make **`dimoapp.xyz`** the primary domain
3. Set **`www.dimoapp.xyz` → redirect to `dimoapp.xyz`** (not the other way)
4. Confirm `curl -sI https://dimoapp.xyz` returns **200** (not 308)
5. Google Cloud OAuth homepage = `https://dimoapp.xyz` (no www)
6. Privacy / terms on the same host

### Or: www primary
Set OAuth homepage / privacy / terms all to `https://www.dimoapp.xyz/...`
and keep WorkOS redirect `https://www.dimoapp.xyz/callback`.

Do not mix apex in Google Cloud with a site that only serves content on www.

## Homepage content checklist (already in the app)

After you point a custom domain at this deploy, the public `/` page should show:

| Google requirement | On Dimo homepage |
| --- | --- |
| Identify the app/brand | App name **Dimo**, logo, H1 |
| Describe functionality | “What Dimo does” feature list |
| Explain why user data is requested | “Why Dimo requests Google user data” (sign-in + optional Gmail readonly) |
| Privacy policy link matching consent screen | `/privacy` on the same domain |
| Visible without login | Server-rendered public page (not behind auth) |
| Not only a login wall | Marketing + purpose above/beside sign-in |

Logo upload file: `store/oauth-logo.png`

## Temporary note about dimo-silk.vercel.app

Keep using it for development. For **Google OAuth brand / restricted Gmail
verification**, switch homepage + privacy + terms to the custom domain first.
