"use client";

import { useAppActions, useAppState } from "@/store/app-store";
import { Sheet } from "@/components/ui/Sheet";
import { DeleteIconButton } from "@/components/ui/DeleteIconButton";
import { ExpenseEditorForm } from "@/components/forms/ExpenseEditorForm";

export function AddRecurringSheet() {
  const { recurringDraft, recurring } = useAppState();
  const actions = useAppActions();
  const item = recurring.find((candidate) => candidate.id === recurringDraft.id);
  if (!item) return null;
  return (
    <Sheet
      onClose={actions.closeOverlay}
      title="Edit recurring expense"
      titleAlignment="center"
      headerRight={<DeleteIconButton onClick={actions.deleteRecurring} aria-label="Delete recurring" />}
    >
      <ExpenseEditorForm mode="recurring" size="mobile" recurring={item} />
    </Sheet>
  );
}
