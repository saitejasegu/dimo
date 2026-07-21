import type { Recurring } from "@/lib/types";
import { nextOccurrence } from "@/lib/dates";

export function activeRecurring(recs: Recurring[]): Recurring[] {
  return recs.filter((r) => !r.paused);
}

/**
 * Sum of all non-paused recurring charges, normalized to a monthly figure.
 * `amountOf` maps each bill to its amount in the account default currency
 * (foreign bills must be converted before summing); it defaults to the raw
 * `amount` for single-currency callers.
 */
export function monthlyRecurringTotal(
  recs: Recurring[],
  amountOf: (rec: Recurring) => number = (rec) => rec.amount,
): number {
  return activeRecurring(recs).reduce((sum, r) => {
    const amount = amountOf(r);
    return sum + (r.frequency === "yearly" ? amount / 12 : amount);
  }, 0);
}

function withNextDue(recs: Recurring[], now: Date, includePaused = false): { rec: Recurring; due: Date }[] {
  return (includePaused ? recs : activeRecurring(recs))
    .flatMap((rec) => {
      if (!rec.anchorDate || !rec.frequency) return [];
      const due = nextOccurrence(
        { anchorDate: rec.anchorDate, frequency: rec.frequency },
        now,
      );
      return [{ rec, due }];
    })
    .sort((a, b) => a.due.getTime() - b.due.getTime());
}

/** Active bills whose next due date falls in the current calendar month. */
export function upcomingBills(recs: Recurring[], limit?: number, now = new Date()): Recurring[] {
  const dueThisMonth = withNextDue(recs, now)
    .filter(({ due }) => due.getFullYear() === now.getFullYear() && due.getMonth() === now.getMonth())
    .map(({ rec }) => rec);

  return limit == null ? dueThisMonth : dueThisMonth.slice(0, limit);
}

/** All bills, including paused bills, sorted by next due date (any month). */
export function allUpcomingBills(recs: Recurring[], now = new Date()): Recurring[] {
  return withNextDue(recs, now, true).map(({ rec }) => rec);
}

export function recurringSubtitle(rec: Recurring): string {
  const prefix = rec.category ? `${rec.category} · ` : "";
  return prefix + (rec.paused ? "Paused" : rec.due);
}
