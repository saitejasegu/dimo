# Google OAuth branding verification — Dimo

Homepage: `https://dimo-silk.vercel.app`  
Privacy: `https://dimo-silk.vercel.app/privacy`  
Terms: `https://dimo-silk.vercel.app/terms`  
Logo to upload in Google Cloud: `store/oauth-logo.png`

The Cloud Console dialog listing old issues does **not** clear until you finish
the steps below and click **Proceed** for a new review.

## Checklist (do in order)

### 1. Redeploy the website
Push/deploy so the homepage H1 reads **“Dimo — personal expense tracker”** and
shows the purpose section. Confirm in an incognito window.

### 2. Verify domain ownership (this is why issue #1 remains)
The meta tag alone is not enough — Search Console must show **Verified**.

1. Open [Google Search Console](https://search.google.com/search-console) with the
   **same Google account** that owns the Cloud project.
2. Property: URL prefix `https://dimo-silk.vercel.app`
3. If not verified yet: use HTML tag (already on the site) → **Verify**.
4. You must see a green **Ownership verified** state.
5. In Google Cloud → OAuth consent screen → Branding, confirm
   `dimo-silk.vercel.app` is an authorized domain / homepage URL.

### 3. Re-upload the logo (required when Google flags the logo)
In Google Cloud → OAuth consent screen → Branding → **App logo**, upload a
**fresh** file:

`store/oauth-logo.png`

That file is a green square with the white wordmark **Dimo** and ledger bars.
It matches the logo on `https://dimo-silk.vercel.app`.

Tips if Google still rejects the logo:
- Upload the file again after redeploying the homepage (branding must match).
- Use PNG, square, under 1MB (ours is 1024×1024).
- App name must stay exactly **Dimo**.
- Do not use a plain letter “D” or a Google-like mark.

### 4. Request re-verification
In the issues dialog:

1. Select **I have fixed the issues**
2. Click **Proceed**
3. Wait for Google’s new review (can take days)

## Why the dialog still lists issues
That screen is a snapshot of the **last failed** attempt. Website fixes and a
verified Search Console property only count after you click Proceed again.
