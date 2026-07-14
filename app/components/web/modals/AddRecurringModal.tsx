"use client";

import { useAppActions, useAppState } from "@/store/app-store";
import { Modal } from "@/components/ui/Modal";
import { DeleteIconButton } from "@/components/ui/DeleteIconButton";
import { ExpenseEditorForm } from "@/components/forms/ExpenseEditorForm";

export function AddRecurringModal() {
  const { recurringDraft, recurring } = useAppState();
  const actions = useAppActions();
  const item = recurring.find((candidate) => candidate.id === recurringDraft.id);
  if (!item) return null;
  return (
    <Modal
      onClose={actions.closeOverlay}
      width={460}
      title="Edit recurring expense"
      titleAlignment="center"
      headerRight={<DeleteIconButton onClick={actions.deleteRecurring} aria-label="Delete recurring" />}
    >
      <ExpenseEditorForm mode="recurring" size="web" recurring={item} onCancel={actions.closeOverlay} />
    </Modal>
  );
}
