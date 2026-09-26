"use client";

import { useState, type ReactNode } from "react";
import { useAppActions } from "@/store/app-store";
import { useLendingSharing } from "@/store/lending-sharing";
import {
  LendEntryForm,
  lendEditorTitle,
  type LendEditorTarget,
} from "@/components/forms/LendEntryForm";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { DeleteIconButton } from "@/components/ui/DeleteIconButton";
import { Modal } from "@/components/ui/Modal";
import { Sheet } from "@/components/ui/Sheet";

export type Variant = "modal" | "sheet";

/** Bottom sheet on mobile, centered modal on desktop. */
export function Frame({
  variant,
  title,
  onClose,
  headerRight,
  layout = "scroll",
  children,
}: {
  variant: Variant;
  title: string;
  onClose: () => void;
  headerRight?: ReactNode;
  /**
   * "scroll": tall content scrolls as one page. "fill": the frame caps its
   * height and lays children out as a column, so a child can own the scroll.
   */
  layout?: "scroll" | "fill";
  children: ReactNode;
}) {
  const scroll =
    layout === "fill"
      ? "flex max-h-[90dvh] flex-col"
      : "max-h-[90dvh] overflow-y-auto overscroll-contain";
  return variant === "modal" ? (
    <Modal onClose={onClose} width={440} title={title} headerRight={headerRight} className={scroll}>
      {children}
    </Modal>
  ) : (
    <Sheet onClose={onClose} title={title} headerRight={headerRight} className={scroll}>
      {children}
    </Sheet>
  );
}

/** Add or edit a lending entry, with delete when editing. */
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
  const sharing = useLendingSharing();
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
        title="Delete this entry?"
        message={
          editing && sharing.activeConnection(editing.contactId)
            ? `This also removes it for ${editing.contactName}.`
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
