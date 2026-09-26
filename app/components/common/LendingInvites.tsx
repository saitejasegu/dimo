"use client";

import { useMemo, useState } from "react";
import { isSharedLendContact } from "@/lib/types";
import { recentLendContacts } from "@/features/lending/selectors";
import { useAppActions, useAppState } from "@/store/app-store";
import {
  sharingErrorText,
  useLendingSharing,
  type IncomingLendInvite,
  type OutgoingLendInvite,
} from "@/store/lending-sharing";
import { Avatar } from "@/components/ui/Avatar";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";

/**
 * Someone inviting you to track lending together. Accept is one tap; only when
 * you already track someone by that name are you asked whether to merge.
 */
export function IncomingInviteCard({ invite }: { invite: IncomingLendInvite }) {
  const { lends } = useAppState("lends");
  const { showToast } = useAppActions();
  const sharing = useLendingSharing();
  const [askMerge, setAskMerge] = useState(false);
  const sameName = useMemo(() => {
    const name = invite.inviterName.trim().toLowerCase();
    return recentLendContacts(lends, Number.MAX_SAFE_INTEGER).find(
      (contact) =>
        !isSharedLendContact(contact.contactId) &&
        contact.contactName.trim().toLowerCase() === name,
    );
  }, [lends, invite.inviterName]);

  function accept(mergeWith?: string) {
    sharing
      .accept({
        inviteId: invite.inviteId,
        contactId: mergeWith,
        contactName: invite.inviterName,
        history: "both",
      })
      .then(() => showToast(`You’re now tracking lending with ${invite.inviterName}`))
      .catch((cause) => showToast(sharingErrorText(cause)));
  }

  return (
    <Card className="p-4">
      <div className="flex items-center gap-3">
        <Avatar
          initial={invite.inviterName.charAt(0).toUpperCase()}
          src={invite.inviterPhotoUrl}
          size={40}
          radius={12}
          textClassName="text-sm"
        />
        <div className="min-w-0 flex-1">
          <div className="truncate text-sm font-semibold text-ink">{invite.inviterName}</div>
          <div className="mt-0.5 text-xs text-muted">
            {invite.reconnect
              ? "Wants to share with you again"
              : "Invited you to track lending together"}
          </div>
          {invite.inviterEmail ? (
            <div className="mt-0.5 truncate text-xs text-faint">{invite.inviterEmail}</div>
          ) : null}
        </div>
      </div>
      <div className="mt-3 grid grid-cols-2 gap-2">
        <Button
          variant="secondary"
          size="sm"
          onClick={() => {
            sharing
              .decline(invite.inviteId)
              .then(() => showToast("Invite declined"))
              .catch(() => showToast("Couldn’t decline the invite"));
          }}
        >
          Decline
        </Button>
        <Button
          size="sm"
          onClick={() => (sameName && !invite.reconnect ? setAskMerge(true) : accept())}
        >
          Accept
        </Button>
      </div>
      <ConfirmDialog
        open={askMerge}
        tone="primary"
        title={`Merge with your “${sameName?.contactName ?? ""}”?`}
        message="Your entries with them are shared too, so you both see one history."
        confirmLabel="Merge"
        alternateLabel="Keep separate"
        cancelLabel="Cancel"
        onCancel={() => setAskMerge(false)}
        onAlternate={() => {
          setAskMerge(false);
          accept();
        }}
        onConfirm={() => {
          setAskMerge(false);
          accept(sameName?.contactId);
        }}
      />
    </Card>
  );
}

/** Confirms withdrawing an invite that hasn't been accepted yet. */
export function CancelInviteDialog({
  invite,
  onClose,
}: {
  invite: OutgoingLendInvite | null;
  onClose: () => void;
}) {
  const { showToast } = useAppActions();
  const sharing = useLendingSharing();
  return (
    <ConfirmDialog
      open={Boolean(invite)}
      title={`Cancel invite to ${invite?.contactName ?? ""}?`}
      message="They won’t be able to accept it. Your entries with them stay on your side only."
      confirmLabel="Cancel invite"
      cancelLabel="Keep"
      onCancel={onClose}
      onConfirm={() => {
        const target = invite;
        onClose();
        if (!target) return;
        sharing
          .cancel(target.inviteId)
          .then(() => showToast("Invite cancelled"))
          .catch(() => showToast("Couldn’t cancel the invite"));
      }}
    />
  );
}
