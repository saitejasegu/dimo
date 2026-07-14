"use client";

import { useAppActions, useAppState } from "@/store/app-store";
import { Modal } from "@/components/ui/Modal";
import { DeleteIconButton } from "@/components/ui/DeleteIconButton";
import { ExpenseEditorForm } from "@/components/forms/ExpenseEditorForm";

export function TxDetailModal() {
  const { transactions, detailId } = useAppState();
  const actions = useAppActions();
  const transaction = transactions.find((item) => item.id === detailId);
  if (!transaction) return null;
  return (
    <Modal
      onClose={actions.closeDetail}
      width={460}
      title="Edit expense"
      titleAlignment="center"
      headerRight={<DeleteIconButton onClick={actions.deleteDetail} aria-label="Delete expense" />}
    >
      <ExpenseEditorForm mode="transaction" size="web" transaction={transaction} onCancel={actions.closeDetail} />
    </Modal>
  );
}
