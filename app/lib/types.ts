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
  /** Category emoji when available. */
  emoji?: string;
  /** Canonical fields used by the local-first backend. */
  amountMinor?: number;
  occurredAt?: number;
  categoryId?: ID;
  paymentMethodId?: ID | null;
  /** Original currency when entered in a non-default currency (else absent). */
  sourceCurrency?: EnterableCurrency;
  /** Original amount in `sourceCurrency` major units, for display alongside `amount`. */
  sourceAmount?: number;
}

export interface TransactionEditInput {
  name: string;
  amount: number;
  /** Currency the `amount` above is entered in. Defaults to the account currency. */
  currency: EnterableCurrency;
  category: CategoryName;
  paymentMethod: PaymentMethod;
  /** Epoch ms for the edited occurrence. */
  occurredAt: number;
}

/** Client-only input for the unified add-expense editor. */
export interface ExpenseSaveInput {
  name: string;
  amount: number;
  category: CategoryName;
  paymentMethod: PaymentMethod;
  /** Currency the `amount` above is entered in. Defaults to the account currency. */
  currency: EnterableCurrency;
  date: string;
  time: string;
  recurring: boolean;
  frequency: Frequency;
  occurrenceSelection: "all" | "selected";
}

/** Client-only input for editing an existing recurring entity. */
export interface RecurringEditInput {
  name: string;
  amount: number;
  /** Currency the recurring `amount` is denominated in. Defaults to account currency. */
  currency: EnterableCurrency;
  category: CategoryName;
  paymentMethod: PaymentMethod;
  anchorDate: string;
  frequency: Frequency;
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
  emoji?: string;
  amountMinor?: number;
  categoryId?: ID;
  paymentMethodId?: ID | null;
  anchorDate?: string;
  frequency?: "monthly" | "yearly";
  /** Currency the amount is denominated in. Absent = account default currency. */
  currency?: EnterableCurrency;
}

export type LendKind = "lent" | "repaid";

export interface Lend {
  id: ID;
  contactName: string;
  contactId: string;
  amount: number;
  amountMinor: number;
  occurredAt: number;
  comment: string;
  kind: LendKind;
  /** Human-readable time and day labels derived from occurredAt. */
  time: string;
  day: string;
}

/** Category -> monthly limit. `null` means the category has no budget. */
export type CategoryLimits = Record<CategoryName, number | null>;

export type StatsRange = "1W" | "M" | "3M" | "6M" | "1Y" | "2Y";

export type Frequency = "Monthly" | "Yearly";

/** Account default currency (what totals/stats are denominated in). */
export type Currency = "INR" | "USD" | "EUR";

/**
 * Currencies a single expense may be entered in. A superset of {@link Currency};
 * foreign entries are converted into the account default on save. All values are
 * ECB reference currencies supported by the Frankfurter rate source.
 */
export type EnterableCurrency =
  | Currency
  | "GBP"
  | "JPY"
  | "AUD"
  | "CAD"
  | "HKD"
  | "SGD"
  | "CHF"
  | "CNY";

export type WeekStart = "Mon" | "Sun";

export type ThemePreference = "system" | "light" | "dark";

export interface NotificationSettings {
  bills: boolean;
  budget: boolean;
  weekly: boolean;
  large: boolean;
}

export interface Profile {
  name: string;
  email: string;
  photoUrl?: string | null;
}

/** All top-level destinations shared by mobile and web. */
export type ViewKey =
  | "home"
  | "tx"
  | "stats"
  | "recurring"
  | "budgets"
  | "lending"
  | "settings"
  | "account";

/** Which transient overlay (sheet on mobile, modal on web) is open. */
export type OverlayKey = "add" | "recurring" | "category" | null;
