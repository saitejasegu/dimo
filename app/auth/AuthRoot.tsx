"use client";

import { useState, type ReactNode } from "react";
import { AuthKitProvider, useAuth } from "@workos-inc/authkit-react";
import { ConvexProviderWithAuthKit } from "@convex-dev/workos";
import {
  Authenticated,
  AuthLoading,
  ConvexReactClient,
  Unauthenticated,
} from "convex/react";
import { AppStoreProvider, useAppState } from "@/store/app-store";
import { useIsMobile } from "@/hooks/useIsMobile";
import { MobileApp } from "@/components/mobile/MobileApp";
import { WebApp } from "@/components/web/WebApp";
import { UpdateBanner } from "@/components/common/UpdateBanner";
import { Button } from "@/components/ui/Button";

function LoadingScreen() {
  return <div className="min-h-dvh bg-canvas" />;
}

function ResponsiveApp() {
  const isMobile = useIsMobile();
  const { dataReady } = useAppState();

  if (!dataReady || isMobile === null) return <LoadingScreen />;

  return (
    <>
      {isMobile ? <MobileApp /> : <WebApp />}
      <UpdateBanner />
    </>
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
  const socialSignIn = async (provider: "GoogleOAuth" | "AppleOAuth") => {
    const url = new URL(await getSignInUrl());
    url.searchParams.set("provider", provider);
    window.location.assign(url);
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
          <Button fullWidth onClick={() => void socialSignIn("GoogleOAuth")}>
            Continue with Google
          </Button>
          <Button
            fullWidth
            variant="secondary"
            onClick={() => void socialSignIn("AppleOAuth")}
          >
            Continue with Apple
          </Button>
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
          Add NEXT_PUBLIC_WORKOS_CLIENT_ID, NEXT_PUBLIC_WORKOS_REDIRECT_URI, and
          NEXT_PUBLIC_CONVEX_URL, then restart Dimo.
        </p>
        {children}
      </section>
    </main>
  );
}

export function AuthRoot() {
  const clientId = process.env.NEXT_PUBLIC_WORKOS_CLIENT_ID;
  const redirectUri = process.env.NEXT_PUBLIC_WORKOS_REDIRECT_URI;
  const convexUrl = process.env.NEXT_PUBLIC_CONVEX_URL;
  const [convex] = useState(() => (convexUrl ? new ConvexReactClient(convexUrl) : null));

  if (!clientId || !redirectUri || !convex) return <ConfigurationRequired />;

  return (
    <AuthKitProvider
      clientId={clientId}
      redirectUri={redirectUri}
      onRedirectCallback={() => window.location.replace("/")}
    >
      <ConvexProviderWithAuthKit client={convex} useAuth={useAuth}>
        <AuthLoading><LoadingScreen /></AuthLoading>
        <Authenticated><SignedInApp /></Authenticated>
        <Unauthenticated><SignInScreen /></Unauthenticated>
      </ConvexProviderWithAuthKit>
    </AuthKitProvider>
  );
}
