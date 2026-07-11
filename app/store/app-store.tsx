"use client";

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useReducer,
  type Dispatch,
  type ReactNode,
} from "react";
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
  ViewKey,
  WeekStart,
} from "@/lib/types";
import type { Action } from "@/store/actions";
import { reducer } from "@/store/reducer";
import { AppState, createInitialState } from "@/store/state";

const TOAST_DURATION_MS = 1800;

/** Bound action creators — the only way components mutate state. */
export interface AppActions {
  setView: (view: ViewKey) => void;
  openAccount: () => void;
  closeAccount: () => void;

  setFilter: (category: CategoryName | "All") => void;
  setQuery: (query: string) => void;

  setStatsRange: (range: StatsRange) => void;
  setSelectedMonth: (month: string) => void;
  toggleMerchants: () => void;
  openMerchant: (name: string) => void;

  openOverlay: (overlay: Exclude<OverlayKey, null>) => void;
  closeOverlay: () => void;
  openDetail: (id: ID) => void;
  closeDetail: () => void;
  deleteDetail: () => void;

  toggleRecurring: (id: ID) => void;

  setExpenseAmount: (amount: string) => void;
  pressAmountKey: (key: string) => void;
  setExpenseName: (name: string) => void;
  setExpenseCategory: (category: CategoryName) => void;
  setExpensePaymentMethod: (paymentMethod: PaymentMethod) => void;
  saveExpense: () => void;
  managePaymentMethods: () => void;
  addPaymentMethod: (input: PaymentMethodInput) => void;
  editPaymentMethod: (id: ID, input: PaymentMethodInput) => void;
  setDefaultPaymentMethod: (id: ID) => void;
  setPaymentMethodArchived: (id: ID, archived: boolean) => void;
  saveTransactionEdits: (id: ID, input: TransactionEditInput) => void;

  setRecurringName: (name: string) => void;
  setRecurringAmount: (amount: string) => void;
  setRecurringDay: (day: string) => void;
  setRecurringFrequency: (frequency: Frequency) => void;
  setRecurringCategory: (category: CategoryName) => void;
  saveRecurring: () => void;

  setCategoryName: (name: string) => void;
  setCategoryLimit: (limit: string) => void;
  saveCategory: () => void;

  setProfileName: (name: string) => void;
  setProfileEmail: (email: string) => void;
  saveProfile: () => void;
  setCurrency: (currency: Currency) => void;
  setWeekStart: (weekStart: WeekStart) => void;
  setDefaultView: (view: string) => void;
  toggleNotification: (key: keyof NotificationSettings) => void;

  showToast: (message: string) => void;
}

function createActions(dispatch: Dispatch<Action>): AppActions {
  return {
    setView: (view) => dispatch({ type: "SET_VIEW", view }),
    openAccount: () => dispatch({ type: "SET_VIEW", view: "account" }),
    closeAccount: () => dispatch({ type: "SET_VIEW", view: "home" }),

    setFilter: (category) => dispatch({ type: "SET_FILTER", category }),
    setQuery: (query) => dispatch({ type: "SET_QUERY", query }),

    setStatsRange: (range) => dispatch({ type: "SET_STATS_RANGE", range }),
    setSelectedMonth: (month) =>
      dispatch({ type: "SET_SELECTED_MONTH", month }),
    toggleMerchants: () => dispatch({ type: "TOGGLE_MERCHANTS" }),
    openMerchant: (name) => dispatch({ type: "OPEN_MERCHANT", name }),

    openOverlay: (overlay) => dispatch({ type: "OPEN_OVERLAY", overlay }),
    closeOverlay: () => dispatch({ type: "CLOSE_OVERLAY" }),
    openDetail: (id) => dispatch({ type: "OPEN_DETAIL", id }),
    closeDetail: () => dispatch({ type: "CLOSE_DETAIL" }),
    deleteDetail: () => dispatch({ type: "DELETE_DETAIL" }),

    toggleRecurring: (id) => dispatch({ type: "TOGGLE_RECURRING", id }),

    setExpenseAmount: (amount) =>
      dispatch({ type: "SET_EXPENSE_AMOUNT", amount }),
    pressAmountKey: (key) => dispatch({ type: "PRESS_AMOUNT_KEY", key }),
    setExpenseName: (name) => dispatch({ type: "SET_EXPENSE_NAME", name }),
    setExpenseCategory: (category) =>
      dispatch({ type: "SET_EXPENSE_CATEGORY", category }),
    setExpensePaymentMethod: (paymentMethod) =>
      dispatch({ type: "SET_EXPENSE_PAYMENT_METHOD", paymentMethod }),
    saveExpense: () => dispatch({ type: "SAVE_EXPENSE" }),
    managePaymentMethods: () => {
      dispatch({ type: "MANAGE_PAYMENT_METHODS" });
      requestAnimationFrame(() =>
        requestAnimationFrame(() =>
          document.getElementById("payment-methods")?.scrollIntoView({
            behavior: "smooth",
            block: "center",
          }),
        ),
      );
    },
    addPaymentMethod: (input) => dispatch({ type: "ADD_PAYMENT_METHOD", input }),
    editPaymentMethod: (id, input) =>
      dispatch({ type: "EDIT_PAYMENT_METHOD", id, input }),
    setDefaultPaymentMethod: (id) =>
      dispatch({ type: "SET_DEFAULT_PAYMENT_METHOD", id }),
    setPaymentMethodArchived: (id, archived) =>
      dispatch({ type: "SET_PAYMENT_METHOD_ARCHIVED", id, archived }),
    saveTransactionEdits: (id, input) =>
      dispatch({ type: "SAVE_TRANSACTION_EDITS", id, input }),

    setRecurringName: (name) => dispatch({ type: "SET_RECURRING_NAME", name }),
    setRecurringAmount: (amount) =>
      dispatch({ type: "SET_RECURRING_AMOUNT", amount }),
    setRecurringDay: (day) => dispatch({ type: "SET_RECURRING_DAY", day }),
    setRecurringFrequency: (frequency) =>
      dispatch({ type: "SET_RECURRING_FREQUENCY", frequency }),
    setRecurringCategory: (category) =>
      dispatch({ type: "SET_RECURRING_CATEGORY", category }),
    saveRecurring: () => dispatch({ type: "SAVE_RECURRING" }),

    setCategoryName: (name) => dispatch({ type: "SET_CATEGORY_NAME", name }),
    setCategoryLimit: (limit) =>
      dispatch({ type: "SET_CATEGORY_LIMIT", limit }),
    saveCategory: () => dispatch({ type: "SAVE_CATEGORY" }),

    setProfileName: (name) => dispatch({ type: "SET_PROFILE_NAME", name }),
    setProfileEmail: (email) => dispatch({ type: "SET_PROFILE_EMAIL", email }),
    saveProfile: () => dispatch({ type: "SHOW_TOAST", message: "Profile saved" }),
    setCurrency: (currency) => dispatch({ type: "SET_CURRENCY", currency }),
    setWeekStart: (weekStart) => dispatch({ type: "SET_WEEK_START", weekStart }),
    setDefaultView: (view) => dispatch({ type: "SET_DEFAULT_VIEW", view }),
    toggleNotification: (key) =>
      dispatch({ type: "TOGGLE_NOTIFICATION", key }),

    showToast: (message) => dispatch({ type: "SHOW_TOAST", message }),
  };
}

interface AppStoreValue {
  state: AppState;
  actions: AppActions;
}

const AppStoreContext = createContext<AppStoreValue | null>(null);

export function AppStoreProvider({
  children,
  userName,
}: {
  children: ReactNode;
  userName?: string;
}) {
  const [state, dispatch] = useReducer(
    reducer,
    userName,
    createInitialState,
  );
  const actions = useMemo(() => createActions(dispatch), [dispatch]);

  // Auto-dismiss the toast; the nonce ensures repeated messages re-trigger.
  useEffect(() => {
    if (!state.toast) return;
    const timer = setTimeout(
      () => dispatch({ type: "CLEAR_TOAST" }),
      TOAST_DURATION_MS,
    );
    return () => clearTimeout(timer);
  }, [state.toast, state.toastNonce]);

  const value = useMemo<AppStoreValue>(
    () => ({ state, actions }),
    [state, actions],
  );

  return (
    <AppStoreContext.Provider value={value}>
      {children}
    </AppStoreContext.Provider>
  );
}

function useStore(): AppStoreValue {
  const store = useContext(AppStoreContext);
  if (!store) {
    throw new Error("useStore must be used within an AppStoreProvider");
  }
  return store;
}

export function useAppState(): AppState {
  return useStore().state;
}

export function useAppActions(): AppActions {
  return useStore().actions;
}
