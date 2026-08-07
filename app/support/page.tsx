export const metadata = {
  title: "Support — Dimo",
  description: "Get help with the Dimo personal spending app.",
};

const SUPPORT_EMAIL = "segusaiteja12345@gmail.com";

export default function SupportPage() {
  return (
    <main className="h-[var(--app-height,100dvh)] overflow-y-auto overscroll-y-contain bg-canvas font-body text-ink [-webkit-overflow-scrolling:touch] select-text">
      <div className="mx-auto max-w-2xl px-6 py-12">
        <p className="mb-2 text-sm text-muted">Dimo</p>
        <h1 className="mb-4 font-display text-3xl font-semibold">Support</h1>
        <div className="space-y-8 text-[15px] leading-relaxed text-body">
          <section className="space-y-2">
            <h2 className="font-display text-lg font-semibold text-ink">Contact</h2>
            <p>
              For help with sign-in, sync, expenses, budgets, lending, or Email
              suggestions, email{" "}
              <a
                className="font-medium text-green underline decoration-green/30 underline-offset-2"
                href={`mailto:${SUPPORT_EMAIL}`}
              >
                {SUPPORT_EMAIL}
              </a>
              .
            </p>
          </section>

          <section className="space-y-2">
            <h2 className="font-display text-lg font-semibold text-ink">Before writing</h2>
            <ul className="list-disc space-y-1 pl-5">
              <li>Check that your device is online and tap Sync now in Account.</li>
              <li>Include your device type and the exact error message.</li>
              <li>Do not email passwords, OAuth tokens, API keys, or full financial records.</li>
            </ul>
          </section>

          <section className="flex gap-4 text-sm">
            <a
              className="font-medium text-green underline decoration-green/30 underline-offset-2"
              href="/privacy"
            >
              Privacy Policy
            </a>
            <a
              className="font-medium text-green underline decoration-green/30 underline-offset-2"
              href="/terms"
            >
              Terms of Service
            </a>
          </section>
        </div>
      </div>
    </main>
  );
}
