# Google OAuth branding verification — Dimo

Homepage: `https://dimo-silk.vercel.app`  
Privacy: `https://dimo-silk.vercel.app/privacy`  
Terms: `https://dimo-silk.vercel.app/terms`  
OAuth logo file to upload: `store/oauth-logo.png` (also `public/brand/dimo-logo-512.png`)

## After deploying the site

1. Confirm the homepage shows **Dimo**, the product description, and sign-in **without** requiring login.
2. Upload `store/oauth-logo.png` (or `public/brand/dimo-logo-512.png`) as the OAuth consent screen logo in Google Cloud Console.
3. Keep the OAuth app name exactly **Dimo**.

## Domain ownership (required)

Google must see that you control `dimo-silk.vercel.app`:

1. Open [Google Search Console](https://search.google.com/search-console).
2. Add property → URL prefix → `https://dimo-silk.vercel.app`.
3. Choose **HTML tag** verification.
4. Copy the content value from the meta tag (the long token).
5. In Vercel → Project → Settings → Environment Variables, set:

   `NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION` = `<token>`

6. Redeploy, then click Verify in Search Console.
7. Back in Google Cloud OAuth branding, choose **I have fixed the issues** → Proceed.

Alternate: Search Console “HTML file” method — download the file Google gives you into `public/` and redeploy, then verify.
