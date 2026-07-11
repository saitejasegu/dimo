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

export const metadata: Metadata = {
  title: "Dimo — Expenses",
  description: "Track spending, budgets, and recurring bills with Dimo.",
  applicationName: "Dimo",
  manifest: "/site.webmanifest",
  icons: {
    icon: [
      { url: "/favicon.svg", type: "image/svg+xml" },
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

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${spaceGrotesk.variable} ${plexSans.variable}`}>
      <body>
        <Script
          id="ios-standalone-app-height"
          strategy="beforeInteractive"
          dangerouslySetInnerHTML={{ __html: STANDALONE_VH_BOOTSTRAP }}
        />
        {children}
        <Analytics />
        <SpeedInsights />
      </body>
    </html>
  );
}
