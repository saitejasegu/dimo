export const metadata = {
  title: "Privacy Policy — Dimo",
  description: "Privacy policy for the Dimo expenses app.",
};

/** Public privacy policy required for App Store Connect. Host this URL in your listing. */
export default function PrivacyPage() {
  return (
    <main className="mx-auto min-h-dvh max-w-2xl bg-canvas px-6 py-12 font-body text-ink">
      <p className="mb-2 text-sm text-muted">Dimo</p>
      <h1 className="mb-2 font-display text-3xl font-semibold">Privacy Policy</h1>
      <p className="mb-8 text-sm text-muted">Last updated: July 11, 2026</p>

      <div className="space-y-6 text-[15px] leading-relaxed text-body">
        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-ink">Overview</h2>
          <p>
            Dimo is a personal spending tracker. This policy explains what
            information the app handles and how it is used.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-ink">
            Data we store
          </h2>
          <p>
            Expense entries, budgets, recurring bills, payment method labels,
            and profile preferences you enter in the app are stored on your
            device for the purpose of running Dimo. When cloud sync is enabled,
            an encrypted network connection sends a replica to the configured
            Convex deployment so the same data can be restored and synchronized
            across devices.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-ink">
            Data we do not collect
          </h2>
          <p>
            Dimo does not sell personal data. The current version does not
            require an account and does not use your expense data for analytics,
            advertising, or profiling.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-ink">
            Third parties
          </h2>
          <p>
            If you install Dimo from the App Store, Apple may collect standard
            install and diagnostics information under Apple&apos;s privacy
            policy. Dimo itself does not embed third-party ad or tracking SDKs.
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
            Changes
          </h2>
          <p>
            We may update this policy as the product evolves. Material changes will be reflected on this
            page with a new &quot;Last updated&quot; date.
          </p>
        </section>

        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-ink">Contact</h2>
          <p>
            Questions about privacy: replace this with your support email before
            App Store submission (for example, support@yourdomain.com).
          </p>
        </section>
      </div>
    </main>
  );
}
