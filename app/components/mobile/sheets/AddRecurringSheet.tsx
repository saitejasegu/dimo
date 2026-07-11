"use client";

import { useAppActions, useAppState } from "@/store/app-store";
import { Sheet } from "@/components/ui/Sheet";
import { AddRecurringForm } from "@/components/forms/AddRecurringForm";
import { DeleteIconButton } from "@/components/ui/DeleteIconButton";

export function AddRecurringSheet() {
  const { recurringDraft } = useAppState();
  const { closeOverlay, deleteRecurring } = useAppActions();
  const editing = Boolean(recurringDraft.id);

  return (
    <Sheet
      onClose={closeOverlay}
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
      <AddRecurringForm fillFrequency />
    </Sheet>
  );
}
