"use client";

import { useAppActions, useAppState } from "@/store/app-store";
import { Modal } from "@/components/ui/Modal";
import { AddRecurringForm } from "@/components/forms/AddRecurringForm";
import { TrashIcon } from "@/components/ui/icons";

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
          <button
            type="button"
            onClick={deleteRecurring}
            aria-label="Delete recurring"
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl border border-danger-line bg-danger-soft text-danger transition-colors hover:bg-[#fbe9e3]"
          >
            <TrashIcon />
          </button>
        ) : undefined
      }
    >
      <AddRecurringForm onCancel={closeOverlay} />
    </Modal>
  );
}
