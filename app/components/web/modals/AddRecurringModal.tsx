"use client";

import { useAppActions, useAppState } from "@/store/app-store";
import { Modal } from "@/components/ui/Modal";
import { AddRecurringForm } from "@/components/forms/AddRecurringForm";
import { DeleteIconButton } from "@/components/ui/DeleteIconButton";

export function AddRecurringModal() {
  const { recurringDraft } = useAppState();
  const { closeOverlay, deleteRecurring } = useAppActions();
  const editing = Boolean(recurringDraft.id);

  return (
    <Modal
      onClose={closeOverlay}
      width={460}
      title={editing ? "Edit recurring" : "Add recurring"}
      headerRight={
        editing ? (
          <DeleteIconButton
            onClick={deleteRecurring}
            aria-label="Delete recurring"
          />
        ) : undefined
      }
    >
      <AddRecurringForm onCancel={closeOverlay} />
    </Modal>
  );
}
