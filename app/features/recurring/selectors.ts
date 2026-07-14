import type { Recurring } from "@/lib/types";
import { nextOccurrence } from "@/lib/dates";

export function activeRecurring(recs: Recurring[]): Recurring[] {
  return recs.filter((r) => !r.paused);
}

/** Sum of all non-paused recurring charges. */
export function monthlyRecurringTotal(recs: Recurring[]): number {
  return activeRecurring(recs).reduce((sum, r) => sum + (r.frequency === "yearly" ? r.amount / 12 : r.amount), 0);
}

function withNextDue(recs: Recurring[], now: Date): { rec: Recurring; due: Date }[] {
  return activeRecurring(recs)
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

/** All active bills sorted by next due date (any month). */
export function allUpcomingBills(recs: Recurring[], now = new Date()): Recurring[] {
  return withNextDue(recs, now).map(({ rec }) => rec);
}

export function recurringSubtitle(rec: Recurring): string {
  const prefix = rec.category ? `${rec.category} · ` : "";
  return prefix + (rec.paused ? "Paused" : rec.due);
}
