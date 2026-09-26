"use client";

import { useMemo, useState } from "react";
import { isSharedLendContact } from "@/lib/types";
import { recentLendContacts } from "@/features/lending/selectors";
import { useAppActions, useAppState } from "@/store/app-store";
import {
  useLendingSharing,
  type IncomingLendInvite,
  type LendHistoryChoice,
} from "@/store/lending-sharing";
import { Button } from "@/components/ui/Button";
import { Chip } from "@/components/ui/Chip";
import { SegmentedControl } from "@/components/ui/SegmentedControl";

export function errorText(error: unknown) {
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

const HISTORY_OPTIONS = [
  { value: "both", label: "Keep both" },
  { value: "inviter", label: "Keep theirs" },
  { value: "accepter", label: "Keep mine" },
] satisfies Array<{ value: LendHistoryChoice; label: string }>;

/**
 * Accepts or declines an invite, optionally linking a contact the accepter
 * already tracks so their history joins the shared ledger.
 */
export function AcceptInviteForm({
  invite,
  onDone,
}: {
  invite: IncomingLendInvite;
  onDone: () => void;
}) {
  const { showToast } = useAppActions();
  const sharing = useLendingSharing();
  const linkable = useShareableContacts();
  const [linkedContactId, setLinkedContactId] = useState<string | undefined>();
  const [contactName, setContactName] = useState(invite.inviterName);
  const [history, setHistory] = useState<LendHistoryChoice>("both");
  const [working, setWorking] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function run(action: () => Promise<void>, done: string) {
    setWorking(true);
    setError(null);
    try {
      await action();
      showToast(done);
      onDone();
    } catch (cause) {
      setError(errorText(cause));
    } finally {
      setWorking(false);
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <p className="text-sm leading-5 text-ink">
        {invite.inviterName}
        {invite.inviterEmail ? ` (${invite.inviterEmail})` : ""} wants to keep a shared lending
        ledger with you. You’ll both see the same entries, and either of you can edit them.
      </p>
      {linkable.length > 0 ? (
        <div>
          <span className="mb-1.5 block text-xs text-muted">
            Already tracking {invite.inviterName} here?
          </span>
          <div className="flex gap-2 overflow-x-auto pb-1">
            <Chip
              label="No"
              surface="canvas"
              selected={!linkedContactId}
              onClick={() => {
                setLinkedContactId(undefined);
                setContactName(invite.inviterName);
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
                ? `Only ${invite.inviterName}’s past entries are kept; yours with them are deleted so nothing is counted twice.`
                : `Only your past entries are kept; ${invite.inviterName}’s are deleted so nothing is counted twice.`}
          </p>
        </div>
      ) : null}
      <div className="flex gap-2.5">
        <Button
          variant="secondary"
          className="flex-1"
          onClick={() => void run(() => sharing.decline(invite.inviteId), "Invite declined")}
        >
          Decline
        </Button>
        <Button
          className="flex-1"
          enabled={!working}
          onClick={() =>
            void run(
              () =>
                sharing.accept({
                  inviteId: invite.inviteId,
                  contactId: linkedContactId,
                  contactName,
                  history: linkedContactId ? history : "both",
                }),
              `Ledger shared with ${contactName.trim() || invite.inviterName}`,
            )
          }
        >
          {working ? "Accepting…" : "Accept"}
        </Button>
      </div>
      {error ? <p className="text-[13px] text-danger">{error}</p> : null}
    </div>
  );
}
