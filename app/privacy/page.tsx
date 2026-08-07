export const metadata = {
  title: "Privacy Policy — Dimo",
  description:
    "How Dimo handles account data, expenses, sync, lending contacts, and optional email suggestions.",
};

/** Swap this before App Store / production hosting. */
const SUPPORT_EMAIL = "segusaiteja12345@gmail.com";

/**
 * Public privacy policy for App Store Connect and the hosted web app.
 * Served at `/privacy` from the static export (`out/privacy/`).
 */
export default function PrivacyPage() {
  // Root html/body are overflow:hidden for the authenticated app shell, so this
  // page must own its own viewport-height scroller.
  return (
    <main className="h-[var(--app-height,100dvh)] overflow-y-auto overscroll-y-contain bg-canvas font-body text-ink [-webkit-overflow-scrolling:touch] select-text">
      <div className="mx-auto max-w-2xl px-6 py-12">
      <p className="mb-2 text-sm text-muted">Dimo</p>
      <h1 className="mb-2 font-display text-3xl font-semibold">Privacy Policy</h1>
      <p className="mb-2 text-sm text-muted">Last updated: August 7, 2026</p>
      <p className="mb-10 text-sm text-muted">
        Also see our{" "}
        <a
          className="font-medium text-green underline decoration-green/30 underline-offset-2"
          href="/terms"
        >
          Terms of Service
        </a>
        .
      </p>

      <div className="space-y-8 text-[15px] leading-relaxed text-body">
        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-ink">Overview</h2>
          <p>
            Dimo is a personal spending tracker for expenses, categories and
            budgets, payment methods, recurring bills, stats, CSV import/export,
            lending, and account preferences. It is available as a web app,
            desktop app, and native mobile apps.
          </p>
          <p>
            Dimo is local-first: your data lives primarily on your device and
            syncs privately to your account when you sign in. This policy
            explains what information is handled, where it goes, and the choices
            you have.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-ink">
            Account information
          </h2>
          <p>
            Sign-in is provided by WorkOS AuthKit (for example Google or Apple
            sign-in). Your sign-in provider supplies your name, email address,
            and optional profile photo. Those profile fields are read-only in
            Dimo. Name and email may be mirrored into workspace metadata so the
            app can show your account when a login token omits them. Profile
            photos from WorkOS are not stored as synced Dimo entities.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-ink">
            Data you create in Dimo
          </h2>
          <p>Depending on which features you use, Dimo may store:</p>
          <ul className="list-disc space-y-1 pl-5">
            <li>Expense transactions (amounts, dates, notes, categories, payment methods)</li>
            <li>Categories, budgets, and payment method labels</li>
            <li>Recurring bills and related schedule details</li>
            <li>Lending records (contact names or contact IDs, amounts, kinds, optional comments)</li>
            <li>App preferences (for example currency and notification toggles)</li>
            <li>
              On native iOS with Email suggestions enabled: analyzed email
              suggestion records, which can include the normalized message body
            </li>
          </ul>
          <p>
            Money amounts are stored as integer minor units. You can export or
            import expenses as CSV; imported files are processed on your device
            to create local records.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-ink">
            Where data is stored
          </h2>
          <p>
            <span className="font-medium text-ink">On your device.</span> Web
            and desktop use a local browser database. iOS uses an on-device
            SQLite database. Android uses an on-device SQLite database. Local
            databases are scoped to your signed-in account.
          </p>
          <p>
            <span className="font-medium text-ink">In the cloud (when signed in).</span>{" "}
            An encrypted connection syncs your Dimo entities to a private Convex
            workspace owned by your authenticated account so data can restore
            and stay consistent across your devices. Ownership is derived from
            your sign-in identity; clients do not choose another user’s account.
          </p>
          <p>
            Address-book contact photos used for lending stay on the device and
            are never persisted or synced as Dimo data. Contact names and IDs
            used for lending may sync with lending records.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-ink">
            Optional Email suggestions (iOS)
          </h2>
          <p>
            On iOS, you may optionally connect Gmail for purchase or refund
            suggestions. Gmail access is read-only and uses Google OAuth. Gmail
            OAuth tokens stay on your device and are not uploaded through Dimo
            sync.
          </p>
          <p>
            Message analysis may use OpenRouter. In “free models” mode, the
            iPhone calls authenticated Convex actions and a shared OpenRouter
            key stays only on the server. In “bring your own key” mode, your
            OpenRouter API key is stored in the device Keychain and analysis
            goes from the iPhone to OpenRouter. Analyzed suggestions (including
            normalized body text) can sync as native-owned email records so they
            restore across your devices. You can disconnect Gmail and delete
            account data as described below.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-ink">
            Analytics and diagnostics
          </h2>
          <p>
            Hosted web and desktop builds may embed Vercel Analytics and Vercel
            Speed Insights to measure traffic and performance (for example page
            views and load timing). Those services do not receive your expense
            entries, budgets, lending records, or email bodies. Native iOS and
            Android builds do not embed those Vercel SDKs.
          </p>
          <p>
            If you install Dimo from the App Store or Google Play, Apple or
            Google may collect standard install and diagnostics information
            under their own policies. Dimo does not embed third-party
            advertising SDKs and does not sell personal data or use your
            spending data for advertising or profiling.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-ink">
            Third parties
          </h2>
          <ul className="list-disc space-y-1 pl-5">
            <li>WorkOS — authentication</li>
            <li>Convex — private cloud sync and related backend functions</li>
            <li>Google / Apple — social sign-in (and Gmail if you connect Email on iOS)</li>
            <li>OpenRouter — optional email analysis when you use that feature</li>
            <li>Vercel — hosting analytics on web/desktop builds only</li>
            <li>Apple / Google — app distribution platforms</li>
          </ul>
          <p>
            Each provider processes relevant data under its own privacy policy
            when you use that provider’s service through Dimo.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-ink">
            How we use information
          </h2>
          <p>Information is used only to:</p>
          <ul className="list-disc space-y-1 pl-5">
            <li>Provide, maintain, and improve Dimo’s features</li>
            <li>Authenticate you and sync your workspace across devices</li>
            <li>Optional email suggestion analysis when you enable it</li>
            <li>Understand aggregate web performance (web/desktop analytics)</li>
            <li>Respond to support or privacy requests you send</li>
          </ul>
        </section>

        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-ink">
            Retention, sign-out, and deletion
          </h2>
          <p>
            Local data remains on the device until you sign out, delete history,
            or delete your account. Sign-out stops sync and deletes local Dimo
            databases on that device before ending the WorkOS session.
          </p>
          <p>
            Account deletion requires a network connection: it clears your cloud
            workspace data, then performs the same local and session cleanup.
            Deleted cloud records are not kept for later restore. Backups you
            create yourself (for example CSV exports) are under your control.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-ink">
            Children
          </h2>
          <p>
            Dimo is not directed at children under 13. Do not use the app to
            store information about children.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-ink">
            Security
          </h2>
          <p>
            Sync uses authenticated, encrypted network connections. Local
            databases and device keychains follow platform storage practices.
            No method of transmission or storage is perfectly secure; please use
            a device passcode or biometrics and keep your sign-in provider
            account protected.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-ink">Changes</h2>
          <p>
            We may update this policy as the product evolves. Material changes
            will be reflected on this page with a new “Last updated” date.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-ink">Contact</h2>
          <p>
            Questions about this privacy policy can be sent to Saiteja Segu at{" "}
            <a
              className="font-medium text-green underline decoration-green/30 underline-offset-2"
              href={`mailto:${SUPPORT_EMAIL}`}
            >
              {SUPPORT_EMAIL}
            </a>
            .
          </p>
        </section>
      </div>
      </div>
    </main>
  );
}
