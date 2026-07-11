import type { Currency, NotificationSettings, WeekStart } from "@/lib/types";

export interface NotificationDef {
  key: keyof NotificationSettings;
  label: string;
  sub: string;
}

export const NOTIFICATION_DEFS: NotificationDef[] = [
  { key: "bills", label: "Bill reminders", sub: "Notified 2 days before a bill is due" },
  { key: "budget", label: "Budget alerts", sub: "When a category crosses 90% of its limit" },
  { key: "weekly", label: "Weekly summary", sub: "A spending recap every Monday" },
  { key: "large", label: "Large transactions", sub: "Any single expense above ₹5,000" },
];

export const CURRENCY_OPTIONS: { value: Currency; label: string }[] = [
  { value: "INR", label: "₹ INR" },
  { value: "USD", label: "$ USD" },
  { value: "EUR", label: "€ EUR" },
];

export const WEEK_START_OPTIONS: { value: WeekStart; label: string }[] = [
  { value: "Mon", label: "Monday" },
  { value: "Sun", label: "Sunday" },
];

/** Screens that can be chosen as the landing view. */
export const DEFAULT_VIEW_OPTIONS = ["Home", "Activity", "Stats"] as const;
