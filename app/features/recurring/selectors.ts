import type { Recurring } from "@/lib/types";
import { nextOccurrence } from "@/lib/dates";

export function activeRecurring(recs: Recurring[]): Recurring[] {
  return recs.filter((r) => !r.paused);
}

/** Sum of all non-paused recurring charges. */
export function monthlyRecurringTotal(recs: Recurring[]): number {
  return activeRecurring(recs).reduce((sum, r) => sum + (r.frequency === "yearly" ? r.amount / 12 : r.amount), 0);
}

/** Active bills whose next due date falls in the current calendar month. */
export function upcomingBills(recs: Recurring[], limit?: number, now = new Date()): Recurring[] {
  const dueThisMonth = activeRecurring(recs)
    .flatMap((rec) => {
      if (!rec.anchorDate || !rec.frequency) return [];
      const due = nextOccurrence(
        { anchorDate: rec.anchorDate, frequency: rec.frequency },
        now,
      );
      const isCurrentMonth =
        due.getFullYear() === now.getFullYear() &&
        due.getMonth() === now.getMonth();
      return isCurrentMonth ? [{ rec, due }] : [];
    })
    .sort((a, b) => a.due.getTime() - b.due.getTime())
    .map(({ rec }) => rec);

  return limit == null ? dueThisMonth : dueThisMonth.slice(0, limit);
}

export function recurringSubtitle(rec: Recurring): string {
  const prefix = rec.category ? `${rec.category} · ` : "";
  return prefix + (rec.paused ? "Paused" : rec.due);
}
