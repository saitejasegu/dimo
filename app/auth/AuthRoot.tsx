"use client";

import { lazy, Suspense, useState, useSyncExternalStore, type ReactNode } from "react";
import { AuthKitProvider, useAuth } from "@workos-inc/authkit-react";
import { ConvexProviderWithAuthKit } from "@convex-dev/workos";
import {
  Authenticated,
  AuthLoading,
  ConvexReactClient,
  Unauthenticated,
} from "convex/react";
import { AppStoreProvider } from "@/store/app-store";
import { useIsMobile } from "@/hooks/useIsMobile";
import { UpdateBanner } from "@/components/common/UpdateBanner";
import {
  LandingPage,
  type AuthProvider,
} from "@/components/marketing/LandingPage";

const MobileApp = lazy(() =>
  import("@/components/mobile/MobileApp").then((m) => ({ default: m.MobileApp })),
);
const WebApp = lazy(() =>
  import("@/components/web/WebApp").then((m) => ({ default: m.WebApp })),
);

function LoadingScreen() {
  return <div className="h-[var(--app-height,100dvh)] bg-canvas" />;
}

/** Public homepage shell — used while auth boots and in static HTML for crawlers. */
function PublicHomeShell({ signInError }: { signInError?: string | null }) {
  return (
    <LandingPage
      onSignIn={() => {}}
      signInReady={false}
      signInError={signInError}
      footerNote={
        <p className="text-center text-xs leading-5 text-muted">
          Preparing secure sign-in…
        </p>
      }
    />
  );
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

function SignInScreen() {
  const { getSignInUrl } = useAuth();
  const [signInError, setSignInError] = useState<string | null>(null);
  const signIn = async (provider: AuthProvider) => {
    if (!window.isSecureContext || !window.crypto?.subtle) {
      setSignInError("Sign-in requires HTTPS. Open Dimo through its HTTPS Tailscale URL.");
      return;
    }

    try {
      const url = new URL(await getSignInUrl());
      url.searchParams.set("provider", provider);
      window.location.assign(url);
    } catch {
      setSignInError("Unable to start sign-in. Check the network connection and try again.");
    }
  };

  return (
    <LandingPage
      onSignIn={(provider) => void signIn(provider)}
      signInError={signInError}
      footerNote={
        <p className="text-center text-xs leading-5 text-muted">
          Your name, email, and profile photo come from your sign-in provider and are
          read-only in Dimo.
        </p>
      }
    />
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

export function AuthRoot() {
  const clientId = process.env.NEXT_PUBLIC_WORKOS_CLIENT_ID;
  const convexUrl = process.env.NEXT_PUBLIC_CONVEX_URL;
  const [convex] = useState(() => (convexUrl ? new ConvexReactClient(convexUrl) : null));
  // Use the server snapshot during hydration, then switch to the active browser
  // origin. This keeps static export hydration deterministic while supporting
  // local, LAN, and Tailscale HTTPS hosts.
  const origin = useSyncExternalStore(
    () => () => {},
    () => window.location.origin,
    () => null,
  );
  const redirectUri = origin ? new URL("/callback", origin).toString() : null;

  if (!clientId || !convex) return <ConfigurationRequired />;
  // Server/static snapshot has no window origin yet — still render the public
  // homepage so Google OAuth review and crawlers see Dimo without a login wall.
  if (!redirectUri) return <PublicHomeShell />;

  return (
    <AuthKitProvider
      clientId={clientId}
      redirectUri={redirectUri}
      // Persist the refresh token across reloads and cold launches. AuthKit
      // removes it when signOutAndClearLocal runs from either account screen.
      devMode
      // Keep AuthKit's freshly exchanged in-memory access token. A full page
      // navigation here would recreate the client before Convex can receive it.
      onRedirectCallback={() => window.history.replaceState({}, "", "/")}
    >
      <ConvexProviderWithAuthKit client={convex} useAuth={useAuth}>
        <AuthLoading><PublicHomeShell /></AuthLoading>
        <Authenticated><SignedInApp /></Authenticated>
        <Unauthenticated><SignInScreen /></Unauthenticated>
      </ConvexProviderWithAuthKit>
    </AuthKitProvider>
  );
}
