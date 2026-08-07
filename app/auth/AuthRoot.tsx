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

/** WorkOS OAuth provider identifiers, passed through on the authorize URL. */
type AuthProvider = "AppleOAuth" | "GoogleOAuth";

function AppleMark() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className="h-[18px] w-[18px]" fill="currentColor">
      <path d="M17.05 20.28c-.98.95-2.05.8-3.08.35-1.09-.46-2.09-.48-3.24 0-1.44.62-2.2.44-3.06-.35C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z" />
    </svg>
  );
}

function GoogleMark() {
  // Monochrome so it sits on the green button, matching the iOS sign-in screen.
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className="h-[18px] w-[18px]" fill="currentColor">
      <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
      <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
      <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
      <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
    </svg>
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
          {/* Apple first: Sign in with Apple must be no less prominent than
              other providers. */}
          <Button
            fullWidth
            variant="contrast"
            leftIcon={<AppleMark />}
            onClick={() => void signIn("AppleOAuth")}
          >
            Sign in with Apple
          </Button>
          <Button fullWidth leftIcon={<GoogleMark />} onClick={() => void signIn("GoogleOAuth")}>
            Sign in with Google
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
