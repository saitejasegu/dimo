export const metadata = {
  title: "Terms of Service — Dimo",
  description: "Terms of service for using the Dimo expenses app.",
};

const SUPPORT_EMAIL = "segusaiteja12345@gmail.com";

/**
 * Public terms for App Store / Play listing and the hosted web app.
 * Served at `/terms` from the static export (`out/terms/`).
 */
export default function TermsPage() {
  // Root html/body are overflow:hidden for the authenticated app shell, so this
  // page must own its own viewport-height scroller.
  return (
    <main className="h-[var(--app-height,100dvh)] overflow-y-auto overscroll-y-contain bg-canvas font-body text-ink [-webkit-overflow-scrolling:touch] select-text">
      <div className="mx-auto max-w-2xl px-6 py-12">
        <p className="mb-2 text-sm text-muted">Dimo</p>
        <h1 className="mb-2 font-display text-3xl font-semibold">Terms of Service</h1>
        <p className="mb-10 text-sm text-muted">Last updated: August 7, 2026</p>

        <div className="space-y-8 text-[15px] leading-relaxed text-body">
          <section className="space-y-2">
            <h2 className="font-display text-lg font-semibold text-ink">Agreement</h2>
            <p>
              These Terms of Service (“Terms”) govern your use of Dimo, a
              personal spending tracker available as web, desktop, and native
              mobile apps (the “Service”), operated by Saiteja Segu (“we”,
              “us”). By creating an account or using Dimo, you agree to these
              Terms. If you do not agree, do not use the Service.
            </p>
            <p>
              Our{" "}
              <a
                className="font-medium text-green underline decoration-green/30 underline-offset-2"
                href="/privacy"
              >
                Privacy Policy
              </a>{" "}
              explains how information is handled and is part of how the
              Service works alongside these Terms.
            </p>
          </section>

          <section className="space-y-2">
            <h2 className="font-display text-lg font-semibold text-ink">
              The Service
            </h2>
            <p>
              Dimo helps you track expenses, categories and budgets, payment
              methods, recurring bills, stats, CSV import/export, lending
              records, and account preferences. Features may differ by
              platform. Optional Email suggestions on iOS (Gmail and related
              analysis) are available only if you choose to enable them.
            </p>
            <p>
              Dimo is provided for personal, non-commercial use. It is not a
              bank, payment processor, tax advisor, accountant, or investment
              service, and it does not provide financial, legal, or tax advice.
            </p>
          </section>

          <section className="space-y-2">
            <h2 className="font-display text-lg font-semibold text-ink">
              Accounts and eligibility
            </h2>
            <p>
              You must be able to form a binding contract and meet the minimum
              age required in your country (and in any case not under 13) to
              use Dimo. You sign in through WorkOS AuthKit (for example Google
              or Apple). You are responsible for keeping access to your
              sign-in provider secure and for activity under your account.
            </p>
            <p>
              Provide accurate information where requested. Do not share your
              account or use another person’s account without permission.
            </p>
          </section>

          <section className="space-y-2">
            <h2 className="font-display text-lg font-semibold text-ink">
              Your content
            </h2>
            <p>
              You retain ownership of the expense, budget, lending, preference,
              and other content you enter into Dimo (“Your Content”). You grant
              us a limited license to host, sync, back up, and process Your
              Content only as needed to operate the Service across your signed-in
              devices.
            </p>
            <p>
              You are responsible for Your Content and for any CSV files you
              import or export. Do not upload unlawful, infringing, or harmful
              material. Lending features may use on-device contacts; contact
              photos stay on your device, while names or IDs you associate with
              lending records may sync with those records.
            </p>
          </section>

          <section className="space-y-2">
            <h2 className="font-display text-lg font-semibold text-ink">
              Acceptable use
            </h2>
            <p>You agree not to:</p>
            <ul className="list-disc space-y-1 pl-5">
              <li>Use Dimo for anything illegal or fraudulent</li>
              <li>Attempt to access another user’s workspace or data</li>
              <li>Probe, disrupt, or overload the Service or its providers</li>
              <li>Reverse engineer the apps except where law allows</li>
              <li>Misuse optional Email/Gmail access beyond Dimo’s intended read-only suggestion features</li>
              <li>Resell, sublicense, or provide Dimo as a hosted service to others without permission</li>
            </ul>
          </section>

          <section className="space-y-2">
            <h2 className="font-display text-lg font-semibold text-ink">
              Third-party services
            </h2>
            <p>
              Dimo relies on third parties such as WorkOS (authentication),
              Convex (sync and backend), Apple and Google (sign-in and app
              distribution), optional Google Gmail and OpenRouter (Email
              suggestions on iOS), and Vercel (web hosting/analytics on
              web/desktop builds). Their terms and privacy policies apply to
              their services. We are not responsible for third-party outages or
              policy changes outside our control.
            </p>
          </section>

          <section className="space-y-2">
            <h2 className="font-display text-lg font-semibold text-ink">
              Subscriptions and fees
            </h2>
            <p>
              Dimo is currently offered free of charge. We may introduce paid
              features later. If we do, we will describe prices and terms in the
              app or store listing before you are charged. App Store or other
              platform purchase rules apply to any in-app purchases made through
              those platforms.
            </p>
          </section>

          <section className="space-y-2">
            <h2 className="font-display text-lg font-semibold text-ink">
              Availability and changes
            </h2>
            <p>
              We aim to keep Dimo available but do not guarantee uninterrupted
              or error-free operation. Features may change, and we may suspend
              or discontinue parts of the Service with reasonable notice when
              practical. Sync depends on network access and third-party
              providers.
            </p>
          </section>

          <section className="space-y-2">
            <h2 className="font-display text-lg font-semibold text-ink">
              Termination
            </h2>
            <p>
              You may stop using Dimo at any time and may sign out or delete
              your account using in-app controls where available. Account
              deletion clears cloud workspace data when online and removes local
              Dimo databases on that device as described in the Privacy Policy.
            </p>
            <p>
              We may suspend or terminate access if you violate these Terms,
              misuse the Service, or create risk for other users or providers.
            </p>
          </section>

          <section className="space-y-2">
            <h2 className="font-display text-lg font-semibold text-ink">
              Disclaimers
            </h2>
            <p>
              THE SERVICE IS PROVIDED “AS IS” AND “AS AVAILABLE.” TO THE
              FULLEST EXTENT PERMITTED BY LAW, WE DISCLAIM WARRANTIES OF
              MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND
              NON-INFRINGEMENT. We do not warrant that totals, budgets, stats,
              exchange estimates, or email suggestions are complete or suitable
              for any financial decision.
            </p>
          </section>

          <section className="space-y-2">
            <h2 className="font-display text-lg font-semibold text-ink">
              Limitation of liability
            </h2>
            <p>
              TO THE FULLEST EXTENT PERMITTED BY LAW, WE ARE NOT LIABLE FOR
              INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES,
              OR FOR LOST PROFITS, DATA, OR GOODWILL, ARISING FROM YOUR USE OF
              DIMO. OUR TOTAL LIABILITY FOR CLAIMS RELATING TO THE SERVICE IS
              LIMITED TO THE GREATER OF (A) THE AMOUNTS YOU PAID US FOR DIMO IN
              THE TWELVE MONTHS BEFORE THE CLAIM OR (B) USD $50, IF YOU HAVE
              PAID NOTHING.
            </p>
            <p>
              Some jurisdictions do not allow certain limitations; in those
              cases, our liability is limited to the maximum extent allowed.
            </p>
          </section>

          <section className="space-y-2">
            <h2 className="font-display text-lg font-semibold text-ink">
              Indemnity
            </h2>
            <p>
              You agree to indemnify and hold us harmless from claims arising
              out of Your Content, your misuse of the Service, or your violation
              of these Terms or applicable law, to the extent permitted by law.
            </p>
          </section>

          <section className="space-y-2">
            <h2 className="font-display text-lg font-semibold text-ink">
              Changes to these Terms
            </h2>
            <p>
              We may update these Terms as the product evolves. Material changes
              will be posted on this page with a new “Last updated” date.
              Continued use after changes become effective constitutes
              acceptance of the updated Terms.
            </p>
          </section>

          <section className="space-y-2">
            <h2 className="font-display text-lg font-semibold text-ink">
              Contact
            </h2>
            <p>
              Questions about these Terms: Saiteja Segu at{" "}
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
