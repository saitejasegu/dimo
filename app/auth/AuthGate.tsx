"use client";

import {
  lazy,
  Suspense,
  useEffect,
  useState,
  useSyncExternalStore,
  type ReactNode,
} from "react";
import { AuthKitProvider, useAuth } from "@workos-inc/authkit-react";
import { ConvexProviderWithAuthKit } from "@convex-dev/workos";
import { ConvexReactClient, useConvexAuth } from "convex/react";
import { AppStoreProvider, type AppUser } from "@/store/app-store";
import { readCachedUser, writeCachedUser } from "@/auth/cachedUser";
import { useIsMobile } from "@/hooks/useIsMobile";
import { UpdateBanner } from "@/components/common/UpdateBanner";

const loadMobileApp = () =>
  import("@/components/mobile/MobileApp").then((m) => ({ default: m.MobileApp }));
const loadWebApp = () =>
  import("@/components/web/WebApp").then((m) => ({ default: m.WebApp }));
const MobileApp = lazy(loadMobileApp);
const WebApp = lazy(loadWebApp);

/**
 * Set by the layout's pre-hydration script when a WorkOS refresh token exists. Read
 * once: the cleanup below removes the attribute as soon as auth settles.
 */
let sessionHint: boolean | null = null;
function hasSessionHint() {
  sessionHint ??= document.documentElement.dataset.authPending === "1";
  return sessionHint;
}

const noopSubscribe = () => () => {};

function LoadingScreen() {
  return <div className="h-[var(--app-height,100dvh)] bg-canvas" />;
}

function ResponsiveApp() {
  const isMobile = useIsMobile();
  return (
    <div className="relative h-[var(--app-height,100dvh)] overflow-hidden">
      <Suspense fallback={<LoadingScreen />}>
        {isMobile ? <MobileApp /> : <WebApp />}
      </Suspense>
      <UpdateBanner />
    </div>
  );
}

function SignedInApp({ user, authReady }: { user: AppUser; authReady: boolean }) {
  return (
    <AppStoreProvider key={user.id} user={user} authReady={authReady}>
      <ResponsiveApp />
    </AppStoreProvider>
  );
}

/**
 * Chooses between the app and the public homepage. A returning session used to wait
 * for the WorkOS token refresh and the Convex auth handshake (~1–2 s of network) before
 * the local database was even opened. With a remembered identity and a live session
 * hint, the app renders from IndexedDB straight away and only sync waits for auth.
 */
function SessionRouter({ children }: { children: ReactNode }) {
  const { isLoading, isAuthenticated } = useConvexAuth();
  const { user } = useAuth();
  const cached = useSyncExternalStore(noopSubscribe, readCachedUser, () => null);
  const hinted = useSyncExternalStore(noopSubscribe, hasSessionHint, () => false);
  const live: AppUser | null = user
    ? {
        id: user.id,
        name: [user.firstName, user.lastName].filter(Boolean).join(" ") || user.email,
        email: user.email,
        photoUrl: user.profilePictureUrl ?? null,
      }
    : null;

  useEffect(() => {
    if (!isAuthenticated || !live) return;
    writeCachedUser({ id: live.id, name: live.name, email: live.email, photoUrl: live.photoUrl });
  }, [isAuthenticated, live?.id, live?.name, live?.email, live?.photoUrl]); // eslint-disable-line react-hooks/exhaustive-deps

  // Start fetching the app shell while auth is still in flight.
  useEffect(() => {
    if (!hinted) return;
    void (window.matchMedia("(max-width: 899px)").matches ? loadMobileApp() : loadWebApp());
  }, [hinted]);

  if (isAuthenticated) {
    if (live) return <SignedInApp user={live} authReady />;
    // Keep the already-painted cached app mounted until AuthKit exposes the user.
    return cached && hinted ? <SignedInApp user={cached} authReady={false} /> : <LoadingScreen />;
  }
  if (isLoading) {
    if (cached && hinted) return <SignedInApp user={cached} authReady={false} />;
    return (
      <>
        <div data-public-home>{children}</div>
        <div data-auth-loading aria-hidden className="hidden">
          <LoadingScreen />
        </div>
      </>
    );
  }
  return <>{children}</>;
}

function ConfigurationRequired({ children }: { children?: ReactNode }) {
  return (
    <main className="flex min-h-dvh items-center justify-center bg-canvas p-6">
      <section className="max-w-lg rounded-2xl border border-line bg-surface p-6 text-sm text-body">
        <h1 className="font-display text-xl font-semibold text-ink">Authentication setup required</h1>
        <p className="mt-2">
          Add NEXT_PUBLIC_WORKOS_CLIENT_ID and NEXT_PUBLIC_CONVEX_URL, then restart Dimo.
        </p>
        {children}
      </section>
    </main>
  );
}

/** Drop the pre-hydration cover once AuthKit/Convex know signed-in vs signed-out. */
function AuthPendingCleanup() {
  const { isLoading } = useConvexAuth();
  useEffect(() => {
    if (!isLoading) {
      delete document.documentElement.dataset.authPending;
      document.getElementById("auth-pending-style")?.remove();
    }
  }, [isLoading]);
  return null;
}

/**
 * Public homepage stays in the static HTML for OAuth brand-verification crawlers.
 * While auth is resolving, returning sessions see a blank canvas (see layout bootstrap
 * + `[data-auth-pending]` CSS) instead of a sign-in flash.
 */
export function AuthGate({ children }: { children: ReactNode }) {
  const clientId = process.env.NEXT_PUBLIC_WORKOS_CLIENT_ID;
  const convexUrl = process.env.NEXT_PUBLIC_CONVEX_URL;
  const [convex] = useState(() => (convexUrl ? new ConvexReactClient(convexUrl) : null));
  // Prefer the live origin (LAN/Tailscale); fall back to the public site for SSR
  // so AuthKitProvider wraps the homepage in the static HTML export.
  const origin = useSyncExternalStore(
    () => () => {},
    () => window.location.origin,
    () => "https://dimoapp.xyz",
  );
  const redirectUri = new URL("/callback", origin).toString();

  if (!clientId || !convex) return <ConfigurationRequired />;

  return (
    <AuthKitProvider
      clientId={clientId}
      redirectUri={redirectUri}
      devMode
      onRedirectCallback={() => window.history.replaceState({}, "", "/")}
    >
      <ConvexProviderWithAuthKit client={convex} useAuth={useAuth}>
        <AuthPendingCleanup />
        <SessionRouter>{children}</SessionRouter>
      </ConvexProviderWithAuthKit>
    </AuthKitProvider>
  );
}
