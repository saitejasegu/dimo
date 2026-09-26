"use client";

import { useState, type ReactNode } from "react";
import { useAppActions } from "@/store/app-store";
import { useLendingSharing } from "@/store/lending-sharing";
import {
  LendEntryForm,
  lendEditorTitle,
  type LendEditorTarget,
} from "@/components/forms/LendEntryForm";
import { AcceptInviteForm } from "@/components/forms/LedgerSharingForms";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { DeleteIconButton } from "@/components/ui/DeleteIconButton";
import { Modal } from "@/components/ui/Modal";
import { Sheet } from "@/components/ui/Sheet";

type Variant = "modal" | "sheet";

function Frame({
  variant,
  title,
  onClose,
  headerRight,
  children,
}: {
  variant: Variant;
  title: string;
  onClose: () => void;
  headerRight?: ReactNode;
  children: ReactNode;
}) {
  return variant === "modal" ? (
    <Modal onClose={onClose} width={440} title={title} headerRight={headerRight}>
      {children}
    </Modal>
  ) : (
    <Sheet onClose={onClose} title={title} headerRight={headerRight}>
      {children}
    </Sheet>
  );
}

const DELETE_TITLES = {
  lent: "Delete this lend?",
  repaid: "Delete this repayment?",
  borrowed: "Delete this borrowing?",
  returned: "Delete this payment?",
} as const;

/** Add / settle / edit a lending entry, with delete when editing. */
export function LendEditorDialog({
  variant,
  target,
  onClose,
}: {
  variant: Variant;
  target: LendEditorTarget;
  onClose: () => void;
}) {
  const { deleteLend } = useAppActions();
  const [confirmDelete, setConfirmDelete] = useState(false);
  const editing = target.mode === "edit" ? target.lend : null;

  return (
    <>
      <Frame
        variant={variant}
        title={lendEditorTitle(target)}
        onClose={onClose}
        headerRight={
          editing ? (
            <DeleteIconButton onClick={() => setConfirmDelete(true)} aria-label="Delete lending entry" />
          ) : undefined
        }
      >
        <LendEntryForm target={target} onDone={onClose} />
      </Frame>
      <ConfirmDialog
        open={confirmDelete && Boolean(editing)}
        title={editing ? DELETE_TITLES[editing.kind] : "Delete?"}
        message={
          editing?.contactId.startsWith("dimo:")
            ? `This also removes it from ${editing.contactName}’s shared ledger.`
            : "This can’t be undone."
        }
        confirmLabel="Delete"
        onCancel={() => setConfirmDelete(false)}
        onConfirm={() => {
          setConfirmDelete(false);
          if (editing) deleteLend(editing.id);
          onClose();
        }}
      />
    </>
  );
}

/** The accept dialog for an incoming invite, when open. */
export function LedgerSharingDialogs({ variant }: { variant: Variant }) {
  const { dialog, setDialog } = useLendingSharing();
  if (!dialog) return null;
  const close = () => setDialog(null);
  return (
    <Frame variant={variant} title="Shared ledger invite" onClose={close}>
      <AcceptInviteForm invite={dialog.invite} onDone={close} />
    </Frame>
  );
}
