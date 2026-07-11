"use client";

import { useAppActions, useAppState } from "@/store/app-store";
import { Modal } from "@/components/ui/Modal";
import { EditExpenseForm } from "@/components/forms/EditExpenseForm";

export function TxDetailModal() {
  const { transactions, detailId } = useAppState();
  const actions = useAppActions();

  const transaction = transactions.find((t) => t.id === detailId);
  if (!transaction) return null;

  return (
    <Modal onClose={actions.closeDetail} width={440}>
      <EditExpenseForm transaction={transaction} size="web" />
    </Modal>
  );
}
