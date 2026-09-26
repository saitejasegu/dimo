"use client";

import { useMemo, useState } from "react";
import { isSharedLendContact } from "@/lib/types";
import { recentLendContacts } from "@/features/lending/selectors";
import { useAppActions, useAppState } from "@/store/app-store";
import {
  groupedInviteCode,
  inviteLink,
  inviteMessage,
  normalizeInviteCode,
  useLendInvitePreview,
  useLendingSharing,
  type LendHistoryChoice,
  type LendInviteCode,
  type LendInvitePreview,
} from "@/store/lending-sharing";
import { Button } from "@/components/ui/Button";
import { Chip } from "@/components/ui/Chip";
import { SegmentedControl } from "@/components/ui/SegmentedControl";
import { TextField } from "@/components/ui/TextField";

function errorText(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  // Convex prefixes server errors with request metadata; keep the sentence.
  const tail = message.split("Uncaught Error:").pop() ?? message;
  return tail.trim().split("\n")[0];
}

function useShareableContacts() {
  const { lends } = useAppState("lends");
  return useMemo(
    () => recentLendContacts(lends, 20).filter((contact) => !isSharedLendContact(contact.contactId)),
    [lends],
  );
}

/**
 * Invites another Dimo account to share a lending ledger by link/code and
 * optionally by their verified email.
 */
export function LedgerInviteForm({
  initialContactId,
  initialContactName,
  onDone,
}: {
  initialContactId?: string;
  initialContactName: string;
  onDone: () => void;
}) {
  const { profile } = useAppState("profile");
  const { showToast } = useAppActions();
  const sharing = useLendingSharing();
  const shareable = useShareableContacts();
  const [contactName, setContactName] = useState(initialContactName);
  const [contactId, setContactId] = useState<string | undefined>(initialContactId);
  const [email, setEmail] = useState("");
  const [invite, setInvite] = useState<LendInviteCode | null>(() => {
    const pending = initialContactId ? sharing.pendingInvite(initialContactId) : undefined;
    return pending ? { code: pending.code, expiresAt: pending.expiresAt } : null;
  });
  const [sentByEmail, setSentByEmail] = useState(false);
  const [working, setWorking] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function create() {
    setWorking(true);
    setError(null);
    try {
      const created = await sharing.createInvite({ contactId, contactName, email });
      setInvite(created);
      setSentByEmail(email.trim().length > 0);
    } catch (cause) {
      setError(errorText(cause));
    } finally {
      setWorking(false);
    }
  }

  async function share(code: string) {
    const text = inviteMessage(profile.name || "A Dimo user", code);
    if (typeof navigator.share === "function") {
      try {
        await navigator.share({ text });
        return;
      } catch {
        // Cancelled or unsupported payload: fall back to copying.
      }
    }
    await navigator.clipboard?.writeText(text);
    showToast("Invite copied");
  }

  if (invite) {
    return (
      <div className="flex flex-col gap-4">
        {sentByEmail ? (
          <p className="text-[13px] leading-5 text-muted">
            If {contactName} uses Dimo with that email, they’ll see your invite in their Lending
            tab.
          </p>
        ) : null}
        <div className="rounded-2xl border border-line bg-canvas py-5 text-center">
          <div className="select-all font-display text-[28px] font-semibold tracking-wide text-ink">
            {groupedInviteCode(invite.code)}
          </div>
          <div className="mt-1 text-xs text-muted">
            Expires {new Date(invite.expiresAt).toLocaleDateString()}
          </div>
        </div>
        <Button fullWidth onClick={() => void share(invite.code)}>
          Share invite
        </Button>
        <div className="flex gap-2.5">
          <Button
            variant="secondary"
            className="flex-1"
            onClick={() => {
              void navigator.clipboard?.writeText(inviteLink(invite.code));
              showToast("Invite link copied");
            }}
          >
            Copy link
          </Button>
          <Button
            variant="danger"
            className="flex-1"
            onClick={() => {
              sharing
                .cancel(invite.code)
                .then(() => {
                  showToast("Invite cancelled");
                  onDone();
                })
                .catch((cause) => setError(errorText(cause)));
            }}
          >
            Cancel invite
          </Button>
        </div>
        {error ? <p className="text-[13px] text-danger">{error}</p> : null}
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <p className="text-[13px] leading-5 text-muted">
        You and the other person see the same entries, and either of you can add, edit or delete
        them.
      </p>
      <div>
        <TextField
          label="Who are you sharing with?"
          value={contactName}
          readOnly={Boolean(initialContactId)}
          onChange={(value) => {
            setContactName(value);
            if (!initialContactId) setContactId(undefined);
          }}
          placeholder="Their name"
        />
        {!initialContactId && shareable.length > 0 ? (
          <div className="mt-2 flex gap-2 overflow-x-auto pb-1">
            {shareable.map((contact) => (
              <Chip
                key={contact.contactId}
                label={contact.contactName}
                surface="canvas"
                selected={contactId === contact.contactId}
                onClick={() => {
                  setContactName(contact.contactName);
                  setContactId(contact.contactId);
                }}
              />
            ))}
          </div>
        ) : null}
        {contactId ? (
          <p className="mt-1.5 text-xs text-muted">
            Your past entries with {contactName} will be shared too.
          </p>
        ) : null}
      </div>
      {sharing.emailInvitesAvailable ? (
        <div>
          <TextField
            label="Their Dimo email (optional)"
            type="email"
            autoComplete="off"
            value={email}
            onChange={setEmail}
            placeholder="name@example.com"
          />
          <p className="mt-1.5 text-xs leading-5 text-muted">
            If they use Dimo with this email, the invite appears in their Lending tab. You can
            also share the link.
          </p>
        </div>
      ) : null}
      <Button
        fullWidth
        enabled={contactName.trim().length > 0 && !working}
        onClick={() => void create()}
      >
        {working ? "Creating…" : "Create invite"}
      </Button>
      {error ? <p className="text-[13px] text-danger">{error}</p> : null}
    </div>
  );
}

const HISTORY_OPTIONS = [
  { value: "both", label: "Keep both" },
  { value: "inviter", label: "Keep theirs" },
  { value: "accepter", label: "Keep mine" },
] satisfies Array<{ value: LendHistoryChoice; label: string }>;

function unavailableReason(preview: LendInvitePreview) {
  if (preview.isOwnInvite) return "This is your own invite. Share it with the other person instead.";
  if (preview.status === "accepted") return "This invite has already been used.";
  if (preview.status === "revoked") return "This invite was cancelled.";
  return `This invite has expired. Ask ${preview.inviterName} for a new one.`;
}

/**
 * Joins a ledger someone shared: preview the invite, optionally link an
 * existing contact, choose whose history to keep, then accept.
 */
export function JoinLedgerForm({ initialCode, onDone }: { initialCode: string; onDone: () => void }) {
  const { showToast } = useAppActions();
  const sharing = useLendingSharing();
  const linkable = useShareableContacts();
  const [code, setCode] = useState(initialCode);
  // The code being looked up; a link or incoming invite looks up immediately.
  const [submitted, setSubmitted] = useState<string | null>(
    normalizeInviteCode(initialCode) || null,
  );
  const [linkedContactId, setLinkedContactId] = useState<string | undefined>();
  const [contactName, setContactName] = useState<string | null>(null);
  const [history, setHistory] = useState<LendHistoryChoice>("both");
  const [working, setWorking] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [now] = useState(() => Date.now());
  const normalized = normalizeInviteCode(code);
  const preview = useLendInvitePreview(submitted);
  const current = submitted === normalized && preview ? preview : null;
  const notFound = submitted === normalized && preview === null;
  const checking = submitted === normalized && preview === undefined;
  const incoming = sharing.incomingInvites.some((invite) => invite.code === normalized);
  const displayName = contactName ?? current?.inviterName ?? "";

  async function accept() {
    setWorking(true);
    setError(null);
    try {
      await sharing.accept({
        code: normalized,
        contactId: linkedContactId,
        contactName: displayName,
        history: linkedContactId ? history : "both",
      });
      showToast(`Ledger shared with ${displayName.trim()}`);
      onDone();
    } catch (cause) {
      setError(errorText(cause));
    } finally {
      setWorking(false);
    }
  }

  if (!current) {
    return (
      <div className="flex flex-col gap-4">
        <p className="text-[13px] leading-5 text-muted">
          Enter the code from the invite someone shared with you.
        </p>
        <input
          type="text"
          value={code}
          onChange={(event) => setCode(event.target.value)}
          placeholder="ABCDE-12345"
          autoCapitalize="characters"
          autoComplete="off"
          className="w-full rounded-xl border border-line bg-canvas px-3.5 py-[11px] font-display text-xl font-semibold uppercase text-ink outline-none placeholder:text-faint"
        />
        <Button
          fullWidth
          enabled={normalized.length >= 6 && !checking}
          onClick={() => setSubmitted(normalized)}
        >
          {checking ? "Checking…" : "Continue"}
        </Button>
        {notFound ? <p className="text-[13px] text-danger">No invite matches that code.</p> : null}
      </div>
    );
  }

  const acceptable =
    current.status === "pending" && !current.isOwnInvite && current.expiresAt > now;
  if (!acceptable) {
    return (
      <div className="flex flex-col gap-4">
        <p className="text-sm text-muted">{unavailableReason(current)}</p>
        <Button variant="secondary" fullWidth onClick={() => setSubmitted(null)}>
          Try another code
        </Button>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <p className="text-sm leading-5 text-ink">
        {current.inviterName} wants to keep a shared lending ledger with you. You’ll both see the
        same entries, and either of you can edit them.
      </p>
      {linkable.length > 0 ? (
        <div>
          <span className="mb-1.5 block text-xs text-muted">
            Already tracking {current.inviterName} here?
          </span>
          <div className="flex gap-2 overflow-x-auto pb-1">
            <Chip
              label="No"
              surface="canvas"
              selected={!linkedContactId}
              onClick={() => {
                setLinkedContactId(undefined);
                setContactName(current.inviterName);
              }}
            />
            {linkable.map((contact) => (
              <Chip
                key={contact.contactId}
                label={contact.contactName}
                surface="canvas"
                selected={linkedContactId === contact.contactId}
                onClick={() => {
                  setLinkedContactId(contact.contactId);
                  setContactName(contact.contactName);
                }}
              />
            ))}
          </div>
        </div>
      ) : null}
      {linkedContactId ? (
        <div>
          <span className="mb-1.5 block text-xs text-muted">If you both recorded the same loans</span>
          <SegmentedControl options={HISTORY_OPTIONS} value={history} onChange={setHistory} />
          <p className="mt-1.5 text-xs leading-5 text-muted">
            {history === "both"
              ? "Both of your past entries are added to the shared ledger."
              : history === "inviter"
                ? `Only ${current.inviterName}’s past entries are kept; yours with them are deleted so nothing is counted twice.`
                : `Only your past entries are kept; ${current.inviterName}’s are deleted so nothing is counted twice.`}
          </p>
        </div>
      ) : null}
      <TextField
        label="Show them as"
        value={displayName}
        onChange={setContactName}
        placeholder={current.inviterName}
      />
      <Button fullWidth enabled={!working} onClick={() => void accept()}>
        {working ? "Joining…" : "Join ledger"}
      </Button>
      {incoming ? (
        <Button
          variant="danger"
          fullWidth
          onClick={() => {
            sharing
              .decline(normalized)
              .then(onDone)
              .catch((cause) => setError(errorText(cause)));
          }}
        >
          Decline
        </Button>
      ) : null}
      {error ? <p className="text-[13px] text-danger">{error}</p> : null}
    </div>
  );
}
