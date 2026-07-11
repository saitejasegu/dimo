import type {
  CategoryLimits,
  NotificationSettings,
  Recurring,
  Transaction,
} from "@/lib/types";

/**
 * Seed data layer.
 *
 * This module is the single source of initial app state. When a backend is
 * introduced, replace these constants with API/query results — the store and
 * every selector already consume the domain types, so nothing downstream needs
 * to change.
 */

export const SEED_TRANSACTIONS: Transaction[] = [
  { id: "t1", name: "Blue Tokai Coffee", category: "Dining", time: "8:42 AM", day: "Today", amount: 280, green: true },
  { id: "t2", name: "Swiggy", category: "Dining", time: "1:15 PM", day: "Today", amount: 430 },
  { id: "t3", name: "Auto Rickshaw", category: "Transit", time: "6:05 PM", day: "Today", amount: 300 },
  { id: "t4", name: "BigBasket", category: "Groceries", time: "11:20 AM", day: "Yesterday", amount: 1890 },
  { id: "t5", name: "Netflix", category: "Bills", time: "9:00 AM", day: "Yesterday", amount: 649, green: true },
  { id: "t6", name: "Metro Recharge", category: "Transit", time: "8:10 AM", day: "Sunday, Jul 6", amount: 600 },
  { id: "t7", name: "Nykaa", category: "Shopping", time: "4:40 PM", day: "Sunday, Jul 6", amount: 2280 },
  { id: "t8", name: "Zepto", category: "Groceries", time: "7:32 PM", day: "Saturday, Jul 5", amount: 740 },
  { id: "t9", name: "Uber", category: "Transit", time: "9:48 PM", day: "Saturday, Jul 5", amount: 315 },
];

export const SEED_RECURRING: Recurring[] = [
  { id: "r1", name: "Electricity — BESCOM", category: "Bills", due: "Due Jul 10 · in 2 days", urgent: true, amount: 1480, paused: false, green: true },
  { id: "r2", name: "Airtel Postpaid", category: "Bills", due: "Due Jul 12 · monthly", amount: 599, paused: false },
  { id: "r3", name: "ACT Fibernet", category: "Bills", due: "Due Jul 14 · monthly", amount: 1131, paused: false },
  { id: "r4", name: "Gym — Cult.fit", category: "Bills", due: "Due Jul 18 · monthly", amount: 1299, paused: false },
  { id: "r5", name: "Spotify Duo", category: "Bills", due: "Due Jul 21 · monthly", amount: 149, paused: false },
  { id: "r6", name: "Rent", category: "Bills", due: "Due Aug 1 · monthly", amount: 18000, paused: false },
  { id: "r7", name: "Hotstar", category: "Bills", due: "Due Jul 25 · monthly", amount: 299, paused: true },
];

export const SEED_LIMITS: CategoryLimits = {
  Dining: 4000,
  Groceries: 6000,
  Bills: 3000,
  Transit: 2500,
  Shopping: 5000,
};

export const SEED_NOTIFICATIONS: NotificationSettings = {
  bills: true,
  budget: true,
  weekly: false,
  large: true,
};

export const DEFAULT_USER_NAME = "Saiteja Segu";

/** A label the design hard-codes for the current month context. */
export const TODAY_LABEL = "Wednesday, July 9";
