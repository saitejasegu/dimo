import { AuthGate } from "@/auth/AuthGate";

export default function CallbackPage() {
  return (
    <AuthGate>
      <main className="flex min-h-dvh items-center justify-center bg-canvas font-body">
        <p className="text-sm text-muted">Signing in to Dimo…</p>
      </main>
    </AuthGate>
  );
}
