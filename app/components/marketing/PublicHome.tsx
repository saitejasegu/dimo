import { SignInButtons } from "@/components/marketing/SignInButtons";

/**
 * Server-rendered public homepage for Google OAuth brand verification.
 * Content is in the static HTML — not behind auth or a client-only shell.
 */
export function PublicHome() {
  return (
    <main className="h-[var(--app-height,100dvh)] overflow-y-auto overscroll-y-contain bg-canvas font-body text-ink [-webkit-overflow-scrolling:touch] select-text">
      <div className="relative isolate overflow-hidden">
        <div
          aria-hidden
          className="pointer-events-none absolute inset-x-0 top-0 h-[34rem] bg-[radial-gradient(ellipse_at_top,_rgba(31,157,99,0.16),_transparent_60%)]"
        />

        <header className="relative mx-auto flex max-w-3xl items-center justify-between px-6 pb-4 pt-8">
          <div className="flex items-center gap-3">
            {/* Same file as Google OAuth branding logo */}
            <img
              src="/brand/dimo-logo-512.png"
              alt="Dimo logo"
              width={40}
              height={40}
              className="h-10 w-10 rounded-2xl"
            />
            <span className="font-display text-xl font-semibold tracking-tight text-ink">
              Dimo
            </span>
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
          <p className="mb-3 text-sm font-semibold text-green">Application name: Dimo</p>
          <h1 className="max-w-xl font-display text-4xl font-semibold leading-[1.1] tracking-tight text-ink sm:text-5xl">
            Dimo
          </h1>
          <h2 className="mt-4 max-w-xl font-display text-2xl font-semibold leading-snug text-ink">
            Purpose of the Dimo app
          </h2>
          <p className="mt-4 max-w-xl text-base leading-7 text-body sm:text-lg">
            The purpose of Dimo is to help people track personal spending.
            Dimo is a personal expense tracker for logging everyday expenses,
            setting category budgets, managing recurring bills, reviewing spend
            stats, and optionally suggesting purchases from Gmail on iOS. Your
            data stays on your devices and syncs privately when you sign in.
          </p>

          <div className="mt-8 max-w-md">
            <SignInButtons />
          </div>
        </section>
      </div>

      <section className="mx-auto max-w-3xl border-t border-line px-6 py-12">
        <h2 className="font-display text-2xl font-semibold text-ink">
          What Dimo does
        </h2>
        <p className="mt-3 max-w-2xl text-[15px] leading-7 text-body">
          Dimo is a personal spending tracker for individuals. It is not a bank,
          payment processor, tax advisor, or advertising product. You create and
          manage your own expense data for personal use on web, desktop, and
          mobile.
        </p>
        <ul className="mt-8 space-y-5 text-[15px] leading-7 text-body">
          <li>
            <span className="font-medium text-ink">Log expenses</span>
            {" — "}
            record amounts, categories, payment methods, notes, and dates.
          </li>
          <li>
            <span className="font-medium text-ink">Budgets and recurring bills</span>
            {" — "}
            set monthly category limits and keep subscriptions visible.
          </li>
          <li>
            <span className="font-medium text-ink">Stats</span>
            {" — "}
            review spending by period, category, and merchant.
          </li>
          <li>
            <span className="font-medium text-ink">Lending records</span>
            {" — "}
            track money lent or borrowed with people you know (native apps).
          </li>
          <li>
            <span className="font-medium text-ink">Optional email suggestions (iOS)</span>
            {" — "}
            optionally connect Gmail to surface purchase or refund suggestions
            you review before anything is saved.
          </li>
        </ul>
      </section>

      <section className="mx-auto max-w-3xl border-t border-line px-6 py-12">
        <h2 className="font-display text-2xl font-semibold text-ink">
          Why Dimo requests Google user data
        </h2>
        <p className="mt-3 max-w-2xl text-[15px] leading-7 text-body">
          Dimo requests Google account access only for the purposes below. We do
          not sell Google user data, use it for ads, or use it to train
          unrelated models.
        </p>
        <ul className="mt-8 space-y-5 text-[15px] leading-7 text-body">
          <li>
            <span className="font-medium text-ink">Sign-in (name, email, profile photo)</span>
            {" — "}
            to create and recognize your Dimo account via WorkOS AuthKit so your
            workspace can sync across your devices. These fields are read-only
            in Dimo.
          </li>
          <li>
            <span className="font-medium text-ink">
              Gmail read-only (optional, iOS Email suggestions)
            </span>
            {" — "}
            if you choose to connect Gmail, Dimo uses{" "}
            <code className="text-ink">gmail.readonly</code> access to look for
            purchase and refund emails and suggest expenses you can accept or
            dismiss. Messages are processed to power those suggestions; Gmail
            OAuth tokens stay on your device and are not uploaded through Dimo
            sync. You can disconnect Gmail at any time.
          </li>
        </ul>
        <p className="mt-6 max-w-2xl text-[15px] leading-7 text-body">
          Full details are in our{" "}
          <a
            className="font-medium text-green underline decoration-green/30 underline-offset-2"
            href="/privacy"
          >
            Privacy Policy
          </a>
          . See also the{" "}
          <a
            className="font-medium text-green underline decoration-green/30 underline-offset-2"
            href="/terms"
          >
            Terms of Service
          </a>
          .
        </p>
      </section>

      <section className="mx-auto max-w-3xl border-t border-line px-6 py-12">
        <h2 className="font-display text-2xl font-semibold text-ink">Privacy policy</h2>
        <p className="mt-3 max-w-2xl text-[15px] leading-7 text-body">
          The Dimo privacy policy is published on this same site and must match
          the URL configured on the Google OAuth consent screen:{" "}
          <a
            className="font-medium text-green underline decoration-green/30 underline-offset-2"
            href="/privacy"
          >
            Privacy Policy
          </a>
          .
        </p>
      </section>

      <footer className="mx-auto flex max-w-3xl flex-col gap-2 border-t border-line px-6 py-10 text-sm text-muted sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-2">
          <img
            src="/brand/dimo-logo-512.png"
            alt="Dimo"
            width={28}
            height={28}
            className="h-7 w-7 rounded-lg"
          />
          <span className="font-display font-semibold text-ink">Dimo</span>
        </div>
        <p>© 2026 Saiteja Segu</p>
      </footer>
    </main>
  );
}
