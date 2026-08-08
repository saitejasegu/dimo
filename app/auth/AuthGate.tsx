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
import {
  Authenticated,
  AuthLoading,
  ConvexReactClient,
  Unauthenticated,
  useConvexAuth,
} from "convex/react";
import { AppStoreProvider } from "@/store/app-store";
import { useIsMobile } from "@/hooks/useIsMobile";
import { UpdateBanner } from "@/components/common/UpdateBanner";

const MobileApp = lazy(() =>
  import("@/components/mobile/MobileApp").then((m) => ({ default: m.MobileApp })),
);
const WebApp = lazy(() =>
  import("@/components/web/WebApp").then((m) => ({ default: m.WebApp })),
);

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

function SignedInApp() {
  const { user } = useAuth();
  if (!user) return <LoadingScreen />;
  const name = [user.firstName, user.lastName].filter(Boolean).join(" ") || user.email;
  return (
    <AppStoreProvider
      key={user.id}
      user={{ id: user.id, name, email: user.email, photoUrl: user.profilePictureUrl }}
    >
      <ResponsiveApp />
    </AppStoreProvider>
  );
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
        <AuthLoading>
          <div data-public-home>{children}</div>
          <div data-auth-loading aria-hidden className="hidden">
            <LoadingScreen />
          </div>
        </AuthLoading>
        <Authenticated>
          <SignedInApp />
        </Authenticated>
        <Unauthenticated>{children}</Unauthenticated>
      </ConvexProviderWithAuthKit>
    </AuthKitProvider>
  );
}
