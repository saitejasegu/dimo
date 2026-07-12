import type { Lend } from "@/lib/types";

export interface LendContactSummary {
  contactName: string;
  contactId: string;
  outstanding: number;
  entryCount: number;
  lastOccurredAt: number;
}

export interface LendDayGroup {
  label: string;
  netAmount: number;
  items: Lend[];
}

export function signedLendAmount(lend: Lend): number {
  return lend.kind === "repaid" ? -lend.amount : lend.amount;
}

export function lendingTotals(lends: Lend[]) {
  const lent = lends.reduce(
    (total, lend) => total + (lend.kind === "lent" ? lend.amount : 0),
    0,
  );
  const repaid = lends.reduce(
    (total, lend) => total + (lend.kind === "repaid" ? lend.amount : 0),
    0,
  );
  return {
    outstanding: lent - repaid,
    lent,
    repaid,
  };
}

/** Active contacts ordered by highest outstanding balance. */
export function lendContactSummaries(lends: Lend[]): LendContactSummary[] {
  const summaries = new Map<string, LendContactSummary>();
  const newestFirst = [...lends].sort((a, b) => b.occurredAt - a.occurredAt);

  for (const lend of newestFirst) {
    const current = summaries.get(lend.contactId);
    if (current) {
      current.outstanding += signedLendAmount(lend);
      current.entryCount += 1;
      current.lastOccurredAt = Math.max(current.lastOccurredAt, lend.occurredAt);
      continue;
    }
    summaries.set(lend.contactId, {
      contactName: lend.contactName,
      contactId: lend.contactId,
      outstanding: signedLendAmount(lend),
      entryCount: 1,
      lastOccurredAt: lend.occurredAt,
    });
  }

  return [...summaries.values()]
    .filter((summary) => summary.outstanding > 0.0001)
    .sort(
      (a, b) =>
        b.outstanding - a.outstanding ||
        a.contactName.localeCompare(b.contactName),
    );
}

/** Newest-first history grouped by the display day label. */
export function groupLendsByDay(lends: Lend[]): LendDayGroup[] {
  const groups = new Map<string, Lend[]>();
  for (const lend of [...lends].sort((a, b) => b.occurredAt - a.occurredAt)) {
    const items = groups.get(lend.day);
    if (items) items.push(lend);
    else groups.set(lend.day, [lend]);
  }
  return [...groups].map(([label, items]) => ({
    label,
    netAmount: items.reduce((total, lend) => total + signedLendAmount(lend), 0),
    items,
  }));
}
