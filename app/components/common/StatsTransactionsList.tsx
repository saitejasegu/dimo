"use client";

import { useMemo } from "react";
import type { Currency, Transaction } from "@/lib/types";
import { money } from "@/lib/format";
import { TransactionRow } from "@/components/common/TransactionRow";

export interface StatsSelection {
  kind: "category" | "merchant";
  name: string;
}

interface StatsTransactionsListProps {
  selection: StatsSelection;
  /** Already scoped to the active period — filtered here by name only. */
  transactions: Transaction[];
  currency: Currency;
  periodLabel: string;
  onOpenTransaction: (id: string) => void;
}

/**
 * Body of the stats drill-through. Reads from the active stats scope so it
 * always matches the period on screen, mirroring the iOS sheet. Presentation is
 * platform-specific — web wraps this in `Modal`, mobile in `Sheet`.
 */
export function StatsTransactionsList({
  selection,
  transactions,
  currency,
  periodLabel,
  onOpenTransaction,
}: StatsTransactionsListProps) {
  const matching = useMemo(
    () =>
      transactions.filter((transaction) =>
        selection.kind === "category"
          ? transaction.category === selection.name
          : transaction.name === selection.name,
      ),
    [transactions, selection],
  );

  const total = matching.reduce((sum, transaction) => sum + transaction.amount, 0);

  return (
    <>
      <div className="mb-3 text-xs text-muted">
        {periodLabel} · {matching.length} {matching.length === 1 ? "transaction" : "transactions"} ·{" "}
        {money(total, currency)}
      </div>
      {matching.length === 0 ? (
        <p className="py-8 text-center text-sm text-muted">Nothing in this period.</p>
      ) : (
        <div className="-mx-1 max-h-[55dvh] overflow-y-auto px-1">
          {matching.map((transaction, index) => (
            <TransactionRow
              key={transaction.id}
              transaction={transaction}
              currency={currency}
              layout="list"
              showDay
              dividerTop={index > 0}
              onClick={onOpenTransaction}
            />
          ))}
        </div>
      )}
    </>
  );
}
