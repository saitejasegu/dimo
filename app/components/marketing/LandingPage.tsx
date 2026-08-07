"use client";

import type { ReactNode } from "react";
import { Button } from "@/components/ui/Button";

/** WorkOS OAuth provider identifiers, passed through on the authorize URL. */
export type AuthProvider = "AppleOAuth" | "GoogleOAuth";

function AppleMark() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className="h-[18px] w-[18px]" fill="currentColor">
      <path d="M17.05 20.28c-.98.95-2.05.8-3.08.35-1.09-.46-2.09-.48-3.24 0-1.44.62-2.2.44-3.06-.35C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z" />
    </svg>
  );
}

function GoogleMark() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className="h-[18px] w-[18px]" fill="currentColor">
      <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
      <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
      <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
      <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
    </svg>
  );
}

/** Distinctive Dimo mark: green tile, white D with nested spend bars. */
export function DimoMark({ className = "h-14 w-14" }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 64 64"
      className={className}
      role="img"
      aria-label="Dimo"
    >
      <rect width="64" height="64" rx="16" fill="#1f9d63" />
      <path
        fill="#f5f8f6"
        fillRule="evenodd"
        d="M18 15h16.2c10.4 0 17.3 6.4 17.3 17S44.6 49 34.2 49H18V15Zm11.6 26.8c6 0 9.9-3.6 9.9-9.4s-3.9-9.4-9.9-9.4H24.2v18.8h5.4Z"
      />
      <rect x="27.2" y="28.2" width="10.5" height="2.4" rx="1.2" fill="#1f9d63" />
      <rect x="27.2" y="32.6" width="7.5" height="2.4" rx="1.2" fill="#1f9d63" />
      <rect x="27.2" y="37" width="4.5" height="2.4" rx="1.2" fill="#1f9d63" />
    </svg>
  );
}

interface LandingPageProps {
  onSignIn: (provider: AuthProvider) => void;
  signInError?: string | null;
  /** When false, buttons stay visible but inert (auth still booting). */
  signInReady?: boolean;
  /** Optional slot under the sign-in buttons (e.g. config hints). */
  footerNote?: ReactNode;
}

/**
 * Public homepage for unauthenticated visitors. Required for Google OAuth
 * branding verification: app name, purpose, and brand must be visible without login.
 */
export function LandingPage({
  onSignIn,
  signInError,
  signInReady = true,
  footerNote,
}: LandingPageProps) {
  return (
    <main className="h-[var(--app-height,100dvh)] overflow-y-auto overscroll-y-contain bg-canvas font-body text-ink [-webkit-overflow-scrolling:touch] select-text">
      <div className="relative isolate overflow-hidden">
        <div
          aria-hidden
          className="pointer-events-none absolute inset-x-0 top-0 h-[34rem] bg-[radial-gradient(ellipse_at_top,_rgba(31,157,99,0.16),_transparent_60%)]"
        />

        <header className="relative mx-auto flex max-w-3xl items-center justify-between px-6 pb-4 pt-8">
          <div className="flex items-center gap-3">
            <DimoMark className="h-10 w-10" />
            <span className="font-display text-xl font-semibold tracking-tight text-ink">Dimo</span>
          </div>
          <nav className="flex items-center gap-4 text-sm text-muted">
            <a className="hover:text-ink" href="/privacy">
              Privacy
            </a>
            <a className="hover:text-ink" href="/terms">
              Terms
            </a>
          </nav>
        </header>

        <section className="relative mx-auto max-w-3xl px-6 pb-10 pt-10 sm:pt-16">
          <p className="mb-4 font-display text-sm font-semibold uppercase tracking-[0.14em] text-green">
            Dimo
          </p>
          <h1 className="max-w-xl font-display text-4xl font-semibold leading-[1.1] tracking-tight text-ink sm:text-5xl">
            Track spending without the clutter.
          </h1>
          <p className="mt-5 max-w-xl text-base leading-7 text-body sm:text-lg">
            Dimo is a personal expense tracker for everyday spending, budgets,
            recurring bills, and stats. Your data stays on your devices and
            syncs privately when you sign in.
          </p>

          <div
            id="sign-in"
            className={`mt-8 max-w-md space-y-3 ${signInReady ? "" : "pointer-events-none opacity-60"}`}
          >
            <Button
              fullWidth
              variant="contrast"
              leftIcon={<AppleMark />}
              onClick={() => onSignIn("AppleOAuth")}
            >
              Sign in with Apple
            </Button>
            <Button fullWidth leftIcon={<GoogleMark />} onClick={() => onSignIn("GoogleOAuth")}>
              Sign in with Google
            </Button>
            {signInError ? (
              <p className="text-center text-sm text-danger">{signInError}</p>
            ) : null}
            {footerNote}
          </div>
        </section>
      </div>

      <section className="mx-auto max-w-3xl border-t border-line px-6 py-12">
        <h2 className="font-display text-2xl font-semibold text-ink">What Dimo does</h2>
        <p className="mt-3 max-w-2xl text-[15px] leading-7 text-body">
          Dimo helps people manage personal finances in one calm place. It is
          built for individual use — not banking, payments, ads, or selling your
          spending data.
        </p>
        <ul className="mt-8 space-y-5 text-[15px] leading-7 text-body">
          <li>
            <span className="font-medium text-ink">Log expenses quickly</span>
            {" — "}
            categories, payment methods, notes, and dates on web, desktop, and
            mobile.
          </li>
          <li>
            <span className="font-medium text-ink">Budgets and recurring bills</span>
            {" — "}
            see monthly limits and keep subscriptions in view.
          </li>
          <li>
            <span className="font-medium text-ink">Stats over time</span>
            {" — "}
            review where money went by period, category, and merchant.
          </li>
          <li>
            <span className="font-medium text-ink">Lending records</span>
            {" — "}
            track money lent or borrowed with people you know (native apps).
          </li>
          <li>
            <span className="font-medium text-ink">Optional email suggestions (iOS)</span>
            {" — "}
            connect Gmail with read-only access to surface purchase or refund
            suggestions you can review before anything is saved. Gmail tokens
            stay on your device; you can disconnect anytime.
          </li>
        </ul>
      </section>

      <section className="mx-auto max-w-3xl border-t border-line px-6 py-12">
        <h2 className="font-display text-2xl font-semibold text-ink">Privacy and accounts</h2>
        <p className="mt-3 max-w-2xl text-[15px] leading-7 text-body">
          Sign-in uses WorkOS AuthKit (Google or Apple). Name, email, and
          profile photo come from your sign-in provider and are read-only in
          Dimo. Cloud sync uses your authenticated Convex workspace so your
          data can restore across your own devices.
        </p>
        <p className="mt-4 text-[15px] leading-7 text-body">
          Read the{" "}
          <a
            className="font-medium text-green underline decoration-green/30 underline-offset-2"
            href="/privacy"
          >
            Privacy Policy
          </a>{" "}
          and{" "}
          <a
            className="font-medium text-green underline decoration-green/30 underline-offset-2"
            href="/terms"
          >
            Terms of Service
          </a>
          .
        </p>
      </section>

      <footer className="mx-auto flex max-w-3xl flex-col gap-2 border-t border-line px-6 py-10 text-sm text-muted sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-2">
          <DimoMark className="h-7 w-7" />
          <span className="font-display font-semibold text-ink">Dimo</span>
        </div>
        <p>© 2026 Saiteja Segu</p>
      </footer>
    </main>
  );
}
