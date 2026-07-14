"use client";

import { useAppActions, useAppState } from "@/store/app-store";
import { Sheet } from "@/components/ui/Sheet";
import { DeleteIconButton } from "@/components/ui/DeleteIconButton";
import { ExpenseEditorForm } from "@/components/forms/ExpenseEditorForm";

export function TxDetailSheet() {
  const { transactions, detailId } = useAppState();
  const actions = useAppActions();
  const transaction = transactions.find((item) => item.id === detailId);
  if (!transaction) return null;
  return (
    <Sheet
      onClose={actions.closeDetail}
      title="Edit expense"
      titleAlignment="center"
      headerRight={<DeleteIconButton onClick={actions.deleteDetail} aria-label="Delete expense" />}
    >
      <ExpenseEditorForm mode="transaction" size="mobile" transaction={transaction} />
    </Sheet>
  );
}
