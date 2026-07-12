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
import { Button } from "@/components/ui/Button";

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

function SignInScreen() {
  const { getSignInUrl } = useAuth();
  const [signInError, setSignInError] = useState<string | null>(null);
  const signInWithGoogle = async () => {
    if (!window.isSecureContext || !window.crypto?.subtle) {
      setSignInError("Sign-in requires HTTPS. Open Dimo through its HTTPS Tailscale URL.");
      return;
    }

    try {
      const url = new URL(await getSignInUrl());
      url.searchParams.set("provider", "GoogleOAuth");
      window.location.assign(url);
    } catch {
      setSignInError("Unable to start sign-in. Check the network connection and try again.");
    }
  };
  return (
    <main className="flex min-h-dvh items-center justify-center bg-canvas p-6">
      <section className="w-full max-w-[410px] rounded-[28px] border border-line bg-surface p-8 shadow-sm">
        <div className="mb-8 flex h-12 w-12 items-center justify-center rounded-2xl bg-green text-xl font-bold text-white">
          D
        </div>
        <h1 className="font-display text-3xl font-semibold text-ink">Welcome to Dimo</h1>
        <p className="mt-2 text-sm leading-6 text-body">
          Sign in to keep your expenses private and synchronized across your devices.
        </p>
        <div className="mt-8 flex flex-col gap-3">
          <Button fullWidth onClick={() => void signInWithGoogle()}>
            Continue with Google
          </Button>
          {signInError ? <p className="text-center text-sm text-red-600">{signInError}</p> : null}
        </div>
        <p className="mt-6 text-center text-xs leading-5 text-muted">
          Your name, email, and profile photo come from your sign-in provider and are read-only in Dimo.
        </p>
      </section>
    </main>
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
  if (!redirectUri) return <LoadingScreen />;

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
        <AuthLoading><LoadingScreen /></AuthLoading>
        <Authenticated><SignedInApp /></Authenticated>
        <Unauthenticated><SignInScreen /></Unauthenticated>
      </ConvexProviderWithAuthKit>
    </AuthKitProvider>
  );
}
