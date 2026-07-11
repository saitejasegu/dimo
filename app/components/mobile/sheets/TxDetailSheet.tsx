"use client";

import { useAppActions, useAppState } from "@/store/app-store";
import { Sheet } from "@/components/ui/Sheet";
import { EditExpenseForm } from "@/components/forms/EditExpenseForm";

export function TxDetailSheet() {
  const { transactions, detailId } = useAppState();
  const actions = useAppActions();

  const transaction = transactions.find((t) => t.id === detailId);
  if (!transaction) return null;

  return (
    <Sheet onClose={actions.closeDetail}>
      <EditExpenseForm transaction={transaction} size="mobile" />
    </Sheet>
  );
}
