"use client";

import { useAppActions } from "@/store/app-store";
import { Sheet } from "@/components/ui/Sheet";
import { ExpenseEditorForm } from "@/components/forms/ExpenseEditorForm";

export function AddExpenseSheet() {
  const actions = useAppActions();
  return (
    <Sheet onClose={actions.closeOverlay} title="Add expense">
      <ExpenseEditorForm mode="create" size="mobile" />
    </Sheet>
  );
}
