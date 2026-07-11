/**
 * Domain types for the Dimo expenses app.
 *
 * These are intentionally UI-agnostic and mirror what a backend would return,
 * so swapping the data layer for a real API means changing only the
 * data/selectors layers — components keep consuming these shapes.
 */

export type ID = string;

export type CategoryName = string;

export type PaymentMethod = string;

export type PaymentMethodType =
  | "UPI"
  | "Card"
  | "Wallet"
  | "Cash"
  | "Bank";

export interface PaymentMethodOption {
  id: ID;
  name: string;
  type: PaymentMethodType;
  detail: string;
  isDefault: boolean;
  archived: boolean;
}

export interface PaymentMethodInput {
  name: string;
  type: PaymentMethodType;
  detail: string;
}

export function paymentMethodLabel(method: PaymentMethodOption): string {
  if (method.type === "Cash") return method.name;
  return [method.type, method.name, method.detail].filter(Boolean).join(" · ");
}

export interface Transaction {
  id: ID;
  name: string;
  category: CategoryName;
  /** Human-readable time, e.g. "8:42 AM" or "Just now". */
  time: string;
  /** Day bucket used for grouping, e.g. "Today", "Sunday, Jul 6". */
  day: string;
  amount: number;
  paymentMethod?: PaymentMethod;
  /** Whether the category tint should use the brand-green accent. */
  green?: boolean;
}

export interface TransactionEditInput {
  amount: number;
  category: CategoryName;
  paymentMethod: PaymentMethod;
}

export interface Recurring {
  id: ID;
  name: string;
  category: CategoryName;
  /** Human-readable due description, e.g. "Due Jul 12 · monthly". */
  due: string;
  amount: number;
  paused: boolean;
  urgent?: boolean;
  green?: boolean;
}

/** Category -> monthly limit. `null` means the category has no budget. */
export type CategoryLimits = Record<CategoryName, number | null>;

export type StatsRange = "M" | "3M" | "6M" | "1Y";

export type Frequency = "Monthly" | "Yearly";

export type Currency = "INR" | "USD" | "EUR";

export type WeekStart = "Mon" | "Sun";

export interface NotificationSettings {
  bills: boolean;
  budget: boolean;
  weekly: boolean;
  large: boolean;
}

export interface Profile {
  name: string;
  email: string;
}

/** All top-level destinations shared by mobile and web. */
export type ViewKey =
  | "home"
  | "tx"
  | "stats"
  | "recurring"
  | "budgets"
  | "account";

/** Which transient overlay (sheet on mobile, modal on web) is open. */
export type OverlayKey = "add" | "recurring" | "category" | null;
