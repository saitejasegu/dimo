import type {
  CategoryLimits,
  CategoryName,
  Currency,
  Frequency,
  ID,
  NotificationSettings,
  OverlayKey,
  Profile,
  Recurring,
  StatsRange,
  Transaction,
  ViewKey,
  WeekStart,
} from "@/lib/types";
import {
  DEFAULT_USER_NAME,
  SEED_LIMITS,
  SEED_NOTIFICATIONS,
  SEED_RECURRING,
  SEED_TRANSACTIONS,
} from "@/data/seed";

export interface ExpenseDraft {
  amount: string;
  name: string;
  category: CategoryName;
}

export interface RecurringDraft {
  name: string;
  amount: string;
  day: string;
  frequency: Frequency;
  category: CategoryName;
}

export interface CategoryDraft {
  name: string;
  limit: string;
}

export interface AppState {
  /** Active top-level view. */
  view: ViewKey;

  // ----- Data (backend-owned in the future) -----
  transactions: Transaction[];
  recurring: Recurring[];
  limits: CategoryLimits;

  // ----- Activity filters -----
  filter: CategoryName | "All";
  query: string;

  // ----- Stats controls -----
  statsRange: StatsRange;
  selectedMonth: string | null;
  merchantsExpanded: boolean;

  // ----- Overlays -----
  overlay: OverlayKey;
  detailId: ID | null;

  // ----- Draft forms -----
  expenseDraft: ExpenseDraft;
  recurringDraft: RecurringDraft;
  categoryDraft: CategoryDraft;

  // ----- Account / preferences -----
  profile: Profile;
  currency: Currency;
  weekStart: WeekStart;
  defaultView: string;
  notifications: NotificationSettings;

  // ----- Transient UI -----
  toast: string | null;
  /** Bumps on every toast so identical messages still re-trigger dismissal. */
  toastNonce: number;
}

export const EMPTY_EXPENSE_DRAFT: ExpenseDraft = {
  amount: "",
  name: "",
  category: "Dining",
};

export const EMPTY_RECURRING_DRAFT: RecurringDraft = {
  name: "",
  amount: "",
  day: "",
  frequency: "Monthly",
  category: "Bills",
};

export const EMPTY_CATEGORY_DRAFT: CategoryDraft = {
  name: "",
  limit: "",
};

export function createInitialState(
  userName: string = DEFAULT_USER_NAME,
): AppState {
  return {
    view: "home",
    transactions: SEED_TRANSACTIONS,
    recurring: SEED_RECURRING,
    limits: SEED_LIMITS,
    filter: "All",
    query: "",
    statsRange: "6M",
    selectedMonth: null,
    merchantsExpanded: false,
    overlay: null,
    detailId: null,
    expenseDraft: EMPTY_EXPENSE_DRAFT,
    recurringDraft: EMPTY_RECURRING_DRAFT,
    categoryDraft: EMPTY_CATEGORY_DRAFT,
    profile: {
      name: userName,
      email: userName.toLowerCase().replace(/\s+/g, ".") + "@gmail.com",
    },
    currency: "INR",
    weekStart: "Mon",
    defaultView: "Home",
    notifications: SEED_NOTIFICATIONS,
    toast: null,
    toastNonce: 0,
  };
}
