"use client";

import { useAppActions } from "@/store/app-store";
import { Modal } from "@/components/ui/Modal";
import { ExpenseEditorForm } from "@/components/forms/ExpenseEditorForm";

export function AddExpenseModal() {
  const actions = useAppActions();
  return (
    <Modal onClose={actions.closeOverlay} width={460} title="Add expense">
      <ExpenseEditorForm mode="create" size="web" onCancel={actions.closeOverlay} />
    </Modal>
  );
}
