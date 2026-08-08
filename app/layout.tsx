import type { Metadata, Viewport } from "next";
import { IBM_Plex_Sans, Space_Grotesk } from "next/font/google";
import Script from "next/script";
import { Analytics } from "@vercel/analytics/next";
import { SpeedInsights } from "@vercel/speed-insights/next";
import "./globals.css";

const spaceGrotesk = Space_Grotesk({
  subsets: ["latin"],
  weight: ["500", "600", "700"],
  variable: "--font-space-grotesk",
});

const plexSans = IBM_Plex_Sans({
  subsets: ["latin"],
  weight: ["400", "500", "600"],
  variable: "--font-plex-sans",
});

const googleSiteVerification = process.env.NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION;

export const metadata: Metadata = {
  title: "Dimo — Personal expense tracker",
  description:
    "Dimo is a personal spending tracker for expenses, budgets, recurring bills, and stats. Local-first, with private sync when you sign in.",
  applicationName: "Dimo",
  manifest: "/site.webmanifest",
  metadataBase: new URL("https://dimoapp.xyz"),
  openGraph: {
    title: "Dimo — Personal expense tracker",
    description:
      "Track everyday spending, budgets, and recurring bills. Your data stays on your devices and syncs privately when you sign in.",
    url: "https://dimoapp.xyz",
    siteName: "Dimo",
    images: [{ url: "/brand/dimo-logo-512.png", width: 512, height: 512, alt: "Dimo" }],
    type: "website",
  },
  icons: {
    icon: [
      { url: "/favicon.svg", type: "image/svg+xml" },
      { url: "/brand/dimo-logo-120.png", sizes: "120x120", type: "image/png" },
      { url: "/icon-192.png", sizes: "192x192", type: "image/png" },
      { url: "/icon-512.png", sizes: "512x512", type: "image/png" },
    ],
    apple: [
      { url: "/apple-touch-icon.png", sizes: "180x180", type: "image/png" },
    ],
  },
  appleWebApp: {
    capable: true,
    title: "Dimo",
    // Home-screen PWA: draw under the status bar so the canvas fills the
    // Dynamic Island band (default paints a separate system chrome that goes black).
    statusBarStyle: "black-translucent",
  },
  other: {
    "mobile-web-app-capable": "yes",
    ...(googleSiteVerification
      ? { "google-site-verification": googleSiteVerification }
      : {}),
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  // Single value — media-query variants can leave a dark status chrome while the
  // app theme is still light. Runtime code in app-store keeps this in sync.
  themeColor: "#f5f8f6",
};

/** iOS standalone under-reports 100dvh on cold start; 100vh fills the screen. */
const STANDALONE_VH_BOOTSTRAP = `(function(){try{var n=window.navigator;var standalone=!!n.standalone||window.matchMedia("(display-mode: standalone)").matches||window.matchMedia("(display-mode: fullscreen)").matches;if(standalone){document.documentElement.style.setProperty("--app-height","100vh");}}catch(e){}})();`;

/**
 * Synchronous body script (not next/script): runs before the public homepage HTML
 * is parsed. If a WorkOS session exists, hide sign-in and show a blank canvas so
 * refresh never flashes the marketing buttons.
 */
const AUTH_PENDING_BOOTSTRAP = `(function(){try{var id=${JSON.stringify(process.env.NEXT_PUBLIC_WORKOS_CLIENT_ID ?? "")};if(!id)return;var has=!!(localStorage.getItem("workos:refresh-token:"+id)||localStorage.getItem("workos:refresh-token"));if(!has){var m=document.cookie.match(/(?:^|;\\s*)workos-has-session=([^;]*)/);if(m){var v=decodeURIComponent(m[1]);has=v==="1"||v.split(".").indexOf(id)!==-1;}}if(!has)return;document.documentElement.dataset.authPending="1";var s=document.createElement("style");s.id="auth-pending-style";s.textContent="html[data-auth-pending] [data-public-home]{display:none!important}html[data-auth-pending] [data-auth-loading]{display:block!important}";document.head.appendChild(s);}catch(e){}})();`;

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html
      lang="en"
      className={`${spaceGrotesk.variable} ${plexSans.variable}`}
      suppressHydrationWarning
    >
      <body>
        <Script
          id="ios-standalone-app-height"
          strategy="beforeInteractive"
          dangerouslySetInnerHTML={{ __html: STANDALONE_VH_BOOTSTRAP }}
        />
        <script
          id="auth-pending-bootstrap"
          dangerouslySetInnerHTML={{ __html: AUTH_PENDING_BOOTSTRAP }}
        />
        {children}
        <Analytics />
        <SpeedInsights />
      </body>
    </html>
  );
}
