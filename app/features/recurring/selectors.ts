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
export function upcomingBills(recs: Recurring[], limit: number, now = new Date()): Recurring[] {
  return activeRecurring(recs)
    .filter((rec) => {
      if (!rec.anchorDate || !rec.frequency) return false;
      const due = nextOccurrence(
        { anchorDate: rec.anchorDate, frequency: rec.frequency },
        now,
      );
      return (
        due.getFullYear() === now.getFullYear() &&
        due.getMonth() === now.getMonth()
      );
    })
    .slice(0, limit);
}

export function recurringSubtitle(rec: Recurring): string {
  const prefix = rec.category ? `${rec.category} · ` : "";
  return prefix + (rec.paused ? "Paused" : rec.due);
}
