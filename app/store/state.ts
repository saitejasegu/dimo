import type {
  CategoryLimits,
  CategoryName,
  Currency,
  Frequency,
  ID,
  NotificationSettings,
  OverlayKey,
  PaymentMethod,
  PaymentMethodOption,
  Profile,
  Recurring,
  StatsRange,
  ThemePreference,
  Transaction,
  ViewKey,
  WeekStart,
} from "@/lib/types";
import type { CategoryEntity, PreferencesEntity } from "@/data/model";
import {
  CASH_PAYMENT_METHOD,
  DEFAULT_CATEGORY_EMOJI,
  DEFAULT_CATEGORY_ENTITIES,
  DEFAULT_PREFERENCES,
} from "@/data/model";

export interface ExpenseDraft {
  amount: string;
  name: string;
  category: CategoryName;
  paymentMethod: PaymentMethod;
}

export interface RecurringDraft {
  /** Set when editing an existing recurring bill; null when creating. */
  id: string | null;
  name: string;
  amount: string;
  anchorDate: string;
  frequency: Frequency;
  category: CategoryName;
}

export interface CategoryDraft {
  /** Set when editing an existing category; null when creating. */
  id: string | null;
  name: string;
  emoji: string;
  limit: string;
}

export interface AppState {
  /** True after the first IndexedDB snapshot has been applied. */
  dataReady: boolean;
  /** Active top-level view. */
  view: ViewKey;

  // ----- Data (backend-owned in the future) -----
  transactions: Transaction[];
  recurring: Recurring[];
  categories: CategoryEntity[];
  limits: CategoryLimits;
  paymentMethods: PaymentMethodOption[];
  lastPaymentMethod: PaymentMethod | null;

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
  theme: ThemePreference;
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
  paymentMethod: "UPI · HDFC Debit · ••42",
};

export const EMPTY_RECURRING_DRAFT: RecurringDraft = {
  id: null,
  name: "",
  amount: "",
  anchorDate: "",
  frequency: "Monthly",
  category: "Bills",
};

export const EMPTY_CATEGORY_DRAFT: CategoryDraft = {
  id: null,
  name: "",
  emoji: DEFAULT_CATEGORY_EMOJI,
  limit: "",
};

export const DEFAULT_PAYMENT_METHODS: PaymentMethodOption[] = [{
  ...CASH_PAYMENT_METHOD,
  isDefault: true,
}];

export function createInitialState(
  userName: string = "",
): AppState {
  return {
    dataReady: false,
    view: "home",
    transactions: [],
    recurring: [],
    categories: DEFAULT_CATEGORY_ENTITIES,
    limits: Object.fromEntries(DEFAULT_CATEGORY_ENTITIES.map((c) => [c.name, null])),
    paymentMethods: DEFAULT_PAYMENT_METHODS,
    lastPaymentMethod: null,
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
      email: "",
    },
    currency: DEFAULT_PREFERENCES.currency,
    weekStart: DEFAULT_PREFERENCES.weekStart,
    theme: DEFAULT_PREFERENCES.theme,
    defaultView: DEFAULT_PREFERENCES.defaultView,
    notifications: DEFAULT_PREFERENCES.notifications,
    toast: null,
    toastNonce: 0,
  };
}

export interface HydratedData {
  transactions: Transaction[];
  recurring: Recurring[];
  categories: CategoryEntity[];
  limits: CategoryLimits;
  paymentMethods: PaymentMethodOption[];
  preferences: PreferencesEntity;
  lastPaymentMethod: PaymentMethod | null;
}
