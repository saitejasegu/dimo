"use client";

import { useState } from "react";
import { useAppActions, useAppState } from "@/store/app-store";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";

/** Confirmed delete-history action used in the Account action stack. */
export function TransactionDataActions() {
  const { transactions } = useAppState();
  const { deleteTransactions } = useAppActions();
  const [confirmOpen, setConfirmOpen] = useState(false);
  const count = transactions.length;

  return (
    <>
      <Button
        variant="danger"
        fullWidth
        onClick={count > 0 ? () => setConfirmOpen(true) : undefined}
        className={count === 0 ? "pointer-events-none opacity-50" : undefined}
      >
        {count === 0 ? "No history to delete" : "Delete history"}
      </Button>

      <ConfirmDialog
        open={confirmOpen}
        title="Delete all transactions?"
        message={`This permanently deletes ${count} ${count === 1 ? "transaction" : "transactions"} from this device and the cloud. Budgets, categories, recurring expenses, and preferences will remain. This cannot be undone.`}
        confirmLabel="Delete all"
        onCancel={() => setConfirmOpen(false)}
        onConfirm={() => {
          deleteTransactions(transactions.map((transaction) => transaction.id));
          setConfirmOpen(false);
        }}
      />
    </>
  );
}
