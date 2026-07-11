"use client";

import { useAppActions, useAppState } from "@/store/app-store";
import { Modal } from "@/components/ui/Modal";
import { TransactionDetailContent } from "@/components/forms/TransactionDetailContent";

export function TxDetailModal() {
  const { transactions, detailId, currency } = useAppState();
  const actions = useAppActions();

  const transaction = transactions.find((t) => t.id === detailId);
  if (!transaction) return null;

  return (
    <Modal onClose={actions.closeDetail} width={420}>
      <TransactionDetailContent
        transaction={transaction}
        currency={currency}
        size="web"
      />
    </Modal>
  );
}
