import type {
  CategoryName,
  Currency,
  Frequency,
  ID,
  NotificationSettings,
  OverlayKey,
  PaymentMethod,
  PaymentMethodInput,
  TransactionEditInput,
  StatsRange,
  ThemePreference,
  ViewKey,
  WeekStart,
} from "@/lib/types";
import type { HydratedData } from "@/store/state";

export type Action =
  | { type: "HYDRATE_DATA"; data: HydratedData }
  // navigation
  | { type: "SET_VIEW"; view: ViewKey }
  // activity
  | { type: "SET_FILTER"; category: CategoryName | "All" }
  | { type: "SET_PAYMENT_FILTER"; paymentMethod: PaymentMethod | "All" }
  | { type: "SET_QUERY"; query: string }
  // stats
  | { type: "SET_STATS_RANGE"; range: StatsRange }
  | { type: "SET_SELECTED_MONTH"; month: string }
  | { type: "TOGGLE_MERCHANTS" }
  | { type: "TOGGLE_CATEGORIES" }
  | { type: "OPEN_MERCHANT"; name: string }
  | { type: "OPEN_CATEGORY"; category: CategoryName }
  // overlays
  | { type: "OPEN_OVERLAY"; overlay: Exclude<OverlayKey, null> }
  | { type: "MANAGE_PAYMENT_METHODS" }
  | { type: "CLOSE_OVERLAY" }
  | { type: "OPEN_DETAIL"; id: ID }
  | { type: "CLOSE_DETAIL" }
  | { type: "DELETE_DETAIL" }
  // recurring toggle
  | { type: "TOGGLE_RECURRING"; id: ID }
  // expense draft
  | { type: "SET_EXPENSE_AMOUNT"; amount: string }
  | { type: "PRESS_AMOUNT_KEY"; key: string }
  | { type: "SET_EXPENSE_NAME"; name: string }
  | { type: "SET_EXPENSE_CATEGORY"; category: CategoryName }
  | { type: "SET_EXPENSE_PAYMENT_METHOD"; paymentMethod: PaymentMethod }
  | { type: "SAVE_EXPENSE" }
  | { type: "ADD_PAYMENT_METHOD"; input: PaymentMethodInput }
  | { type: "EDIT_PAYMENT_METHOD"; id: ID; input: PaymentMethodInput }
  | { type: "SET_DEFAULT_PAYMENT_METHOD"; id: ID }
  | { type: "SET_PAYMENT_METHOD_ARCHIVED"; id: ID; archived: boolean }
  | { type: "SAVE_TRANSACTION_EDITS"; id: ID; input: TransactionEditInput }
  // recurring draft
  | { type: "OPEN_EDIT_RECURRING"; id: ID }
  | { type: "SET_RECURRING_NAME"; name: string }
  | { type: "SET_RECURRING_AMOUNT"; amount: string }
  | { type: "SET_RECURRING_ANCHOR_DATE"; anchorDate: string }
  | { type: "SET_RECURRING_FREQUENCY"; frequency: Frequency }
  | { type: "SET_RECURRING_CATEGORY"; category: CategoryName }
  | { type: "SET_RECURRING_PAYMENT_METHOD"; paymentMethod: PaymentMethod }
  | { type: "SAVE_RECURRING" }
  // category draft
  | { type: "OPEN_EDIT_CATEGORY"; id: ID }
  | { type: "SET_CATEGORY_NAME"; name: string }
  | { type: "SET_CATEGORY_EMOJI"; emoji: string }
  | { type: "SET_CATEGORY_LIMIT"; limit: string }
  | { type: "SAVE_CATEGORY" }
  // account
  | { type: "SET_PROFILE_NAME"; name: string }
  | { type: "SET_PROFILE_EMAIL"; email: string }
  | { type: "SET_CURRENCY"; currency: Currency }
  | { type: "SET_WEEK_START"; weekStart: WeekStart }
  | { type: "SET_THEME"; theme: ThemePreference }
  | { type: "SET_DEFAULT_VIEW"; view: string }
  | { type: "SET_DEFAULT_STATS_RANGE"; range: StatsRange }
  | { type: "TOGGLE_NOTIFICATION"; key: keyof NotificationSettings }
  // toast
  | { type: "SHOW_TOAST"; message: string }
  | { type: "CLEAR_TOAST" };
