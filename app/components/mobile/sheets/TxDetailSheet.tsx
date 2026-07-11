"use client";

import { useAppActions, useAppState } from "@/store/app-store";
import { Sheet } from "@/components/ui/Sheet";
import { TransactionDetailContent } from "@/components/forms/TransactionDetailContent";

export function TxDetailSheet() {
  const { transactions, detailId, currency } = useAppState();
  const actions = useAppActions();

  const transaction = transactions.find((t) => t.id === detailId);
  if (!transaction) return null;

  return (
    <Sheet onClose={actions.closeDetail}>
      <TransactionDetailContent
        transaction={transaction}
        currency={currency}
        size="mobile"
      />
    </Sheet>
  );
}
