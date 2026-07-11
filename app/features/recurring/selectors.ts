import type { Recurring } from "@/lib/types";

export function activeRecurring(recs: Recurring[]): Recurring[] {
  return recs.filter((r) => !r.paused);
}

/** Sum of all non-paused recurring charges. */
export function monthlyRecurringTotal(recs: Recurring[]): number {
  return activeRecurring(recs).reduce((sum, r) => sum + (r.frequency === "yearly" ? r.amount / 12 : r.amount), 0);
}

export function upcomingBills(recs: Recurring[], limit: number): Recurring[] {
  return activeRecurring(recs).slice(0, limit);
}

export function recurringSubtitle(rec: Recurring): string {
  const prefix = rec.category ? `${rec.category} · ` : "";
  return prefix + (rec.paused ? "Paused" : rec.due);
}
