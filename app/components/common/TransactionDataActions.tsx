"use client";

import { useRef, useState, type ChangeEvent } from "react";
import { useAppActions, useAppState } from "@/store/app-store";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import {
  formatTransactionCsv,
  parseTransactionCsv,
  TRANSACTION_CSV_TEMPLATE,
} from "@/features/transactions/csv";

function downloadCsv(contents: string, filename: string) {
  const url = URL.createObjectURL(new Blob([contents], { type: "text/csv;charset=utf-8" }));
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}

/** Confirmed delete-history action used in the Account action stack. */
export function TransactionDataActions() {
  const { transactions, recurring } = useAppState();
  const { deleteHistory, importTransactions, showToast } = useAppActions();
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [importing, setImporting] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const transactionCount = transactions.length;
  const recurringCount = recurring.length;
  const count = transactionCount + recurringCount;

  const exportTemplate = () => {
    downloadCsv(TRANSACTION_CSV_TEMPLATE, "dimo-transaction-import-template.csv");
  };

  const exportTransactions = () => {
    if (transactionCount === 0) {
      showToast("No transactions to export");
      return;
    }
    downloadCsv(formatTransactionCsv(transactions), "dimo-transactions.csv");
  };

  const handleImport = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    setImporting(true);
    try {
      const rows = parseTransactionCsv(await file.text());
      await importTransactions(rows);
    } catch (error) {
      showToast(error instanceof Error ? error.message : "Could not import CSV");
    } finally {
      setImporting(false);
    }
  };

  return (
    <>
      <div className="mb-3">
        <h2 className="mb-1 font-display text-base font-semibold text-ink">Transaction data</h2>
        <p className="mb-4 text-xs text-muted">
          Export all expenses as CSV, or import from Dimo&apos;s template.
        </p>
        <input ref={inputRef} type="file" accept=".csv,text/csv" onChange={handleImport} className="hidden" />
        <div className="flex flex-col gap-2.5">
          <Button variant="accent" fullWidth enabled={!importing} onClick={() => inputRef.current?.click()}>
            {importing ? "Importing…" : "Import transactions"}
          </Button>
          <Button
            variant="secondary"
            fullWidth
            onClick={transactionCount > 0 ? exportTransactions : undefined}
            className={transactionCount === 0 ? "pointer-events-none opacity-50" : undefined}
          >
            {transactionCount === 0 ? "No transactions to export" : "Export transactions"}
          </Button>
          <Button variant="secondary" fullWidth onClick={exportTemplate}>Export CSV template</Button>
        </div>
      </div>
      <div className="my-4 h-px bg-line-soft" />
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
        title="Delete history?"
        message={`This permanently deletes ${transactionCount} ${transactionCount === 1 ? "transaction" : "transactions"} and ${recurringCount} recurring ${recurringCount === 1 ? "expense" : "expenses"} from this device and the cloud. Categories, budgets, and preferences will remain. This cannot be undone.`}
        confirmLabel="Delete history"
        onCancel={() => setConfirmOpen(false)}
        onConfirm={() => {
          deleteHistory();
          setConfirmOpen(false);
        }}
      />
    </>
  );
}
