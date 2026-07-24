import type { Recurring, Transaction } from "@/lib/types";
import { localDateKey, nextOccurrence } from "@/lib/dates";

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

/**
 * The bill's next due date that hasn't already been charged. The backend cron
 * materializes each occurrence as a transaction keyed `recurring:<id>:<dateKey>`
 * on its due day, so an occurrence whose transaction already exists is skipped —
 * otherwise a bill charged today would linger in "upcoming" until day's end.
 */
function nextDueUnrecorded(
  rec: Recurring,
  recordedIds: Set<string>,
  now: Date,
): Date {
  const schedule = { anchorDate: rec.anchorDate!, frequency: rec.frequency! };
  let due = nextOccurrence(schedule, now);
  for (let i = 0; i < 24; i++) {
    if (!recordedIds.has(`recurring:${rec.id}:${localDateKey(due)}`)) break;
    // Advance past the recorded occurrence to the following one.
    const dayAfter = new Date(due.getFullYear(), due.getMonth(), due.getDate() + 1);
    due = nextOccurrence(schedule, dayAfter);
  }
  return due;
}

function withNextDue(
  recs: Recurring[],
  transactions: Transaction[],
  now: Date,
  includePaused = false,
): { rec: Recurring; due: Date }[] {
  const recordedIds = new Set(transactions.map((t) => t.id));
  return (includePaused ? recs : activeRecurring(recs))
    .flatMap((rec) => {
      if (!rec.anchorDate || !rec.frequency) return [];
      return [{ rec, due: nextDueUnrecorded(rec, recordedIds, now) }];
    })
    .sort((a, b) => a.due.getTime() - b.due.getTime());
}

/** Active bills whose next unpaid due date falls in the current calendar month. */
export function upcomingBills(
  recs: Recurring[],
  transactions: Transaction[],
  limit?: number,
  now = new Date(),
): Recurring[] {
  const dueThisMonth = withNextDue(recs, transactions, now)
    .filter(({ due }) => due.getFullYear() === now.getFullYear() && due.getMonth() === now.getMonth())
    .map(({ rec }) => rec);

  return limit == null ? dueThisMonth : dueThisMonth.slice(0, limit);
}

/** All bills, including paused bills, sorted by next unpaid due date (any month). */
export function allUpcomingBills(
  recs: Recurring[],
  transactions: Transaction[],
  now = new Date(),
): Recurring[] {
  return withNextDue(recs, transactions, now, true).map(({ rec }) => rec);
}

export function recurringSubtitle(rec: Recurring): string {
  const prefix = rec.category ? `${rec.category} · ` : "";
  return prefix + (rec.paused ? "Paused" : rec.due);
}
