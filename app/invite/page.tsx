import { InviteRedirect } from "@/invite/InviteRedirect";

export const metadata = {
  title: "Shared ledger invite — Dimo",
  description: "Join a shared lending ledger on Dimo.",
};

export default function InvitePage() {
  return (
    <main className="flex min-h-dvh items-center justify-center bg-canvas font-body">
      <InviteRedirect />
    </main>
  );
}
