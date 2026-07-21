"use client";

import {
  createContext,
  useContext,
  useEffect,
  useLayoutEffect,
  useMemo,
  useReducer,
  type Dispatch,
  type ReactNode,
} from "react";
import { useLiveQuery } from "dexie-react-hooks";
import { useConvex } from "convex/react";
import { makeFunctionReference } from "convex/server";
import { activateUserDatabase, db, type SyncMetaRecord } from "@/data/db";
import {
  CASH_PAYMENT_METHOD,
  DEFAULT_CATEGORY_EMOJI,
  DEFAULT_PREFERENCES,
  WORKSPACE_ID,
  entityKey,
  type CategoryEntity,
  type LendEntity,
  type PaymentMethodEntity,
  type PreferencesEntity,
  type RecurringEntity,
  type TransactionEntity,
} from "@/data/model";
import {
  initializeLocalDatabase,
  removeEntity,
  saveEntity,
  saveEntities,
  setLastPaymentMethod,
} from "@/data/repository";
import { formatTransactionDay, formatTransactionTime, localDateKey, localDateTimeTimestamp, nextOccurrence, occurrenceTimestamp, occurrencesThrough, recurringDueLabel, recurringTransactionDates } from "@/lib/dates";
import {
  paymentMethodLabel,
  type CategoryName,
  type Currency,
  type ExpenseSaveInput,
  type Frequency,
  type ID,
  type NotificationSettings,
  type OverlayKey,
  type PaymentMethod,
  type PaymentMethodInput,
  type PaymentMethodOption,
  type RecurringEditInput,
  type StatsRange,
  type ThemePreference,
  type TransactionEditInput,
  type ViewKey,
  type WeekStart,
} from "@/lib/types";
import type { Action } from "@/store/actions";
import { reducer } from "@/store/reducer";
import { type AppState, createInitialState } from "@/store/state";
import { requestFullSync, startSync, stopSync } from "@/sync/coordinator";
import {
  categoryEmojiForName,
  defaultPaymentMethodIdForImport,
  type TransactionCsvRow,
} from "@/features/transactions/csv";
import { suggestedCategoryBudgetUpdates } from "@/features/budgets/selectors";
import {
  cacheRates,
  convertMinor,
  loadCachedRates,
  rateBetween,
  recurringEntryFields,
  toMajorUnits,
  toMinorUnits,
  type RateTable,
} from "@/features/currency/rates";
import type { EnterableCurrency } from "@/lib/types";

const TOAST_DURATION_MS = 1800;

const latestRatesRef = makeFunctionReference<"query", Record<string, never>, RateTable | null>(
  "exchangeRates:latest",
);

export interface AppActions {
  setView: (view: ViewKey) => void;
  openSettings: () => void; closeSettings: () => void;
  openAccount: () => void; closeAccount: () => void;
  setFilter: (category: CategoryName | "All") => void;
  setPaymentFilter: (paymentMethod: PaymentMethod | "All") => void;
  setQuery: (query: string) => void;
  setStatsRange: (range: StatsRange) => void; setSelectedMonth: (month: string) => void;
  toggleMerchants: () => void;
  toggleCategories: () => void;
  openMerchant: (name: string) => void;
  openCategory: (category: CategoryName) => void;
  openOverlay: (overlay: Exclude<OverlayKey, null>) => void; closeOverlay: () => void;
  openDetail: (id: ID) => void; closeDetail: () => void; deleteDetail: () => void;
  deleteTransactions: (ids: ID[]) => void;
  deleteHistory: () => void;
  importTransactions: (rows: TransactionCsvRow[]) => Promise<void>;
  toggleRecurring: (id: ID) => void;
  openEditRecurring: (id: ID) => void;
  setExpenseAmount: (amount: string) => void; pressAmountKey: (key: string) => void;
  setExpenseName: (name: string) => void; setExpenseDate: (date: string) => void;
  setExpenseTime: (time: string) => void;
  setExpenseCategory: (category: CategoryName) => void;
  setExpensePaymentMethod: (paymentMethod: PaymentMethod) => void;
  saveExpense: (input: ExpenseSaveInput) => void;
  managePaymentMethods: () => void; addPaymentMethod: (input: PaymentMethodInput) => void;
  editPaymentMethod: (id: ID, input: PaymentMethodInput) => void;
  setDefaultPaymentMethod: (id: ID) => void;
  setPaymentMethodArchived: (id: ID, archived: boolean) => void;
  saveTransactionEdits: (id: ID, input: TransactionEditInput) => void;
  setRecurringName: (name: string) => void; setRecurringAmount: (amount: string) => void;
  setRecurringAnchorDate: (date: string) => void; setRecurringDay: (day: string) => void;
  setRecurringFrequency: (frequency: Frequency) => void;
  setRecurringCategory: (category: CategoryName) => void;
  setRecurringPaymentMethod: (paymentMethod: PaymentMethod) => void;
  saveRecurring: () => void;
  saveRecurringEdits: (id: ID, input: RecurringEditInput) => void;
  deleteRecurring: () => void;
  setCategoryName: (name: string) => void; setCategoryEmoji: (emoji: string) => void;
  setCategoryLimit: (limit: string) => void;
  openEditCategory: (id: ID) => void;
  saveCategory: () => void;
  applySuggestedBudgets: (categoryIds: string[]) => void;
  deleteCategory: () => void;
  setProfileName: (name: string) => void;
  setProfileEmail: (email: string) => void; saveProfile: () => void;
  setCurrency: (currency: Currency) => void; setWeekStart: (weekStart: WeekStart) => void;
  setTheme: (theme: ThemePreference) => void;
  setNavGlassOpacity: (opacity: number, options?: { persist?: boolean }) => void;
  setDefaultStatsRange: (range: StatsRange) => void;
  manageStatsDefaults: () => void;
  toggleNotification: (key: keyof NotificationSettings) => void;
  showToast: (message: string) => void; syncNow: () => void;
}

export interface SyncState extends SyncMetaRecord {
  pending: number;
  blocked: number;
  configured: boolean;
}

function preferencesFrom(state: AppState, patch: Partial<PreferencesEntity> = {}): PreferencesEntity {
  const defaultMethod = state.paymentMethods.find((method) => method.isDefault)?.id ?? CASH_PAYMENT_METHOD.id;
  return {
    ...DEFAULT_PREFERENCES,
    profileName: state.profile.name,
    profileEmail: state.profile.email,
    currency: state.currency,
    weekStart: state.weekStart,
    theme: state.theme,
    navGlassOpacity: state.navGlassOpacity,
    defaultStatsRange: state.defaultStatsRange,
    notifications: state.notifications,
    defaultPaymentMethodId: defaultMethod,
    ...patch,
    defaultView: "home",
  };
}

/** Currency fields for a one-off transaction entered in `currency`. */
type TransactionCurrencyFields = Pick<
  TransactionEntity,
  "amountMinor" | "sourceCurrency" | "sourceAmountMinor" | "exchangeRate"
>;

/**
 * Convert a major-unit `amount` entered in `currency` into a stored transaction
 * amount denominated in `defaultCurrency`. Returns `null` when a foreign amount
 * cannot be converted (rates unavailable) so the caller can abort with a toast
 * rather than store a wrong value.
 */
function convertEntry(
  amount: number,
  currency: EnterableCurrency,
  defaultCurrency: Currency,
  rates: AppState["rates"],
): TransactionCurrencyFields | null {
  const sourceMinor = Math.max(1, toMinorUnits(amount, currency));
  if (currency === defaultCurrency) return { amountMinor: sourceMinor };
  const convertedMinor = convertMinor(sourceMinor, currency, defaultCurrency, rates);
  const ratio = rateBetween(currency, defaultCurrency, rates);
  if (convertedMinor == null || ratio == null) return null;
  return {
    amountMinor: Math.max(1, convertedMinor),
    sourceCurrency: currency,
    sourceAmountMinor: sourceMinor,
    exchangeRate: ratio,
  };
}

function createActions(dispatch: Dispatch<Action>, getState: () => AppState): AppActions {
  const fail = (error: unknown) => dispatch({ type: "SHOW_TOAST", message: `Could not save locally: ${error instanceof Error ? error.message : String(error)}` });
  const persist = (work: Promise<unknown>, onSaved?: () => void) => void work.then(onSaved).catch(fail);
  const scrollToSettingsSection = (id: string) => {
    let attempts = 0;
    const scroll = () => {
      const element = document.getElementById(id);
      if (element) {
        element.scrollIntoView({ behavior: "smooth", block: "center" });
      } else if (attempts < 12) {
        attempts += 1;
        requestAnimationFrame(scroll);
      }
    };
    requestAnimationFrame(scroll);
  };
  return {
    setView: (view) => dispatch({ type: "SET_VIEW", view }),
    openSettings: () => dispatch({ type: "OPEN_SETTINGS" }),
    closeSettings: () => dispatch({ type: "CLOSE_SETTINGS" }),
    openAccount: () => dispatch({ type: "OPEN_ACCOUNT" }),
    closeAccount: () => dispatch({ type: "CLOSE_ACCOUNT" }),
    setFilter: (category) => dispatch({ type: "SET_FILTER", category }),
    setPaymentFilter: (paymentMethod) =>
      dispatch({ type: "SET_PAYMENT_FILTER", paymentMethod }),
    setQuery: (query) => dispatch({ type: "SET_QUERY", query }),
    setStatsRange: (range) => dispatch({ type: "SET_STATS_RANGE", range }), setSelectedMonth: (month) => dispatch({ type: "SET_SELECTED_MONTH", month }),
    toggleMerchants: () => dispatch({ type: "TOGGLE_MERCHANTS" }),
    toggleCategories: () => dispatch({ type: "TOGGLE_CATEGORIES" }),
    openMerchant: (name) => dispatch({ type: "OPEN_MERCHANT", name }),
    openCategory: (category) => dispatch({ type: "OPEN_CATEGORY", category }),
    openOverlay: (overlay) => dispatch({ type: "OPEN_OVERLAY", overlay }), closeOverlay: () => dispatch({ type: "CLOSE_OVERLAY" }),
    openDetail: (id) => dispatch({ type: "OPEN_DETAIL", id }), closeDetail: () => dispatch({ type: "CLOSE_DETAIL" }),
    deleteDetail: () => {
      const id = getState().detailId; if (!id) return;
      persist(removeEntity("transaction", id), () => { dispatch({ type: "CLOSE_DETAIL" }); dispatch({ type: "SHOW_TOAST", message: "Transaction deleted" }); });
    },
    deleteTransactions: (ids) => {
      const unique = [...new Set(ids)];
      if (unique.length === 0) return;
      persist(
        Promise.all(unique.map((id) => removeEntity("transaction", id))),
        () => {
          dispatch({ type: "CLOSE_DETAIL" });
          dispatch({
            type: "SHOW_TOAST",
            message:
              unique.length === 1
                ? "Transaction deleted"
                : `${unique.length} transactions deleted`,
          });
        },
      );
    },
    deleteHistory: () => {
      const state = getState();
      const transactionIds = state.transactions.map((item) => item.id);
      const recurringIds = state.recurring.map((item) => item.id);
      if (transactionIds.length === 0 && recurringIds.length === 0) return;
      persist(
        Promise.all([
          ...transactionIds.map((id) => removeEntity("transaction", id)),
          ...recurringIds.map((id) => removeEntity("recurring", id)),
        ]),
        () => {
          dispatch({ type: "CLOSE_DETAIL" });
          dispatch({ type: "CLOSE_OVERLAY" });
          dispatch({ type: "SHOW_TOAST", message: "History deleted" });
        },
      );
    },
    importTransactions: async (rows) => {
      const state = getState();
      const defaultPaymentMethodId = defaultPaymentMethodIdForImport(
        state.paymentMethods,
      );
      const categoriesByName = new Map(
        state.categories.map((category) => [category.name.toLocaleLowerCase(), category]),
      );
      const newCategories: CategoryEntity[] = [];
      const transactions: TransactionEntity[] = [];
      for (const row of rows) {
        const key = row.category.toLocaleLowerCase();
        let category = categoriesByName.get(key);
        if (!category) {
          category = {
            id: crypto.randomUUID(), name: row.category, emoji: categoryEmojiForName(row.category),
            monthlyBudgetMinor: null, tint: "neutral",
            sortOrder: state.categories.length + newCategories.length, system: false,
          };
          categoriesByName.set(key, category);
          newCategories.push(category);
        }
        transactions.push({
          id: crypto.randomUUID(), name: row.merchant, amountMinor: row.amountMinor,
          occurredAt: row.occurredAt, categoryId: category.id,
          paymentMethodId: defaultPaymentMethodId,
        });
      }
      try {
        await saveEntities([
          ...newCategories.map((payload) => ({ entityType: "category" as const, payload })),
          ...transactions.map((payload) => ({ entityType: "transaction" as const, payload })),
        ]);
        dispatch({ type: "SHOW_TOAST", message: `${transactions.length} transaction${transactions.length === 1 ? "" : "s"} imported` });
      } catch (error) {
        throw error;
      }
    },
    toggleRecurring: (id) => {
      const state = getState(); const row = state.recurring.find((item) => item.id === id); if (!row?.anchorDate || !row.categoryId) return;
      const entity: RecurringEntity = { id, name: row.name, amountMinor: row.amountMinor ?? Math.round(row.amount * 100), categoryId: row.categoryId, paymentMethodId: row.paymentMethodId ?? null, frequency: row.frequency ?? "monthly", anchorDate: row.anchorDate, paused: !row.paused, currency: row.currency ?? state.currency };
      persist(saveEntity("recurring", entity), () => {
        dispatch({ type: "CLOSE_OVERLAY" });
        dispatch({ type: "SHOW_TOAST", message: entity.paused ? `${entity.name} paused` : `${entity.name} resumed` });
      });
    },
    openEditRecurring: (id) => dispatch({ type: "OPEN_EDIT_RECURRING", id }),
    setExpenseAmount: (amount) => dispatch({ type: "SET_EXPENSE_AMOUNT", amount }), pressAmountKey: (key) => dispatch({ type: "PRESS_AMOUNT_KEY", key }),
    setExpenseName: (name) => dispatch({ type: "SET_EXPENSE_NAME", name }), setExpenseDate: (date) => dispatch({ type: "SET_EXPENSE_DATE", date }),
    setExpenseTime: (time) => dispatch({ type: "SET_EXPENSE_TIME", time }),
    setExpenseCategory: (category) => dispatch({ type: "SET_EXPENSE_CATEGORY", category }),
    setExpensePaymentMethod: (paymentMethod) => dispatch({ type: "SET_EXPENSE_PAYMENT_METHOD", paymentMethod }),
    saveExpense: (input) => {
      const state = getState();
      const category = state.categories.find((c) => c.name === input.category);
      const method = state.paymentMethods.find((m) => paymentMethodLabel(m) === input.paymentMethod);
      if (!(input.amount > 0) || !category) return;
      const name = input.name.trim() || input.category;
      const currency = input.currency;

      if (!input.recurring) {
        const converted = convertEntry(input.amount, currency, state.currency, state.rates);
        if (!converted) { dispatch({ type: "SHOW_TOAST", message: "Exchange rates unavailable — try again once online" }); return; }
        const entity: TransactionEntity = {
          id: crypto.randomUUID(), name, ...converted,
          occurredAt: localDateTimeTimestamp(input.date, input.time),
          categoryId: category.id, paymentMethodId: method?.id ?? null,
        };
        persist(Promise.all([saveEntity("transaction", entity), setLastPaymentMethod(method?.id ?? null)]), () => {
          dispatch({ type: "CLOSE_OVERLAY" }); dispatch({ type: "SET_VIEW", view: "home" }); dispatch({ type: "SHOW_TOAST", message: "Expense added" });
        });
        return;
      }

      if (!input.name.trim() || !/^\d{4}-\d{2}-\d{2}$/.test(input.date)) return;
      const recurring: RecurringEntity = {
        id: crypto.randomUUID(), name: input.name.trim(),
        ...recurringEntryFields(input.amount, currency),
        categoryId: category.id, paymentMethodId: method?.id ?? null,
        frequency: input.frequency.toLowerCase() as "monthly" | "yearly",
        anchorDate: input.date, paused: false,
      };
      const transactionDates = recurringTransactionDates(recurring, input.occurrenceSelection);
      // Backfilled occurrences convert with the latest cached rate. Abort rather
      // than record a wrong default amount when a foreign entry has no rate.
      const converted = convertEntry(input.amount, currency, state.currency, state.rates);
      if (!converted) { dispatch({ type: "SHOW_TOAST", message: "Exchange rates unavailable — try again once online" }); return; }
      const entities: Parameters<typeof saveEntities>[0] = [
        { entityType: "recurring", payload: recurring },
        ...transactionDates.map((date): Parameters<typeof saveEntities>[0][number] => ({
          entityType: "transaction",
          payload: {
            id: crypto.randomUUID(), name: recurring.name, ...converted,
            occurredAt: occurrenceTimestamp(date, input.time), categoryId: recurring.categoryId,
            paymentMethodId: recurring.paymentMethodId,
          } satisfies TransactionEntity,
        })),
      ];
      persist(Promise.all([saveEntities(entities), setLastPaymentMethod(method?.id ?? null)]), () => {
        dispatch({ type: "CLOSE_OVERLAY" }); dispatch({ type: "SET_VIEW", view: "home" });
        dispatch({ type: "SHOW_TOAST", message: transactionDates.length > 0 ? `${recurring.name} added · ${transactionDates.length} transaction${transactionDates.length === 1 ? "" : "s"}` : `${recurring.name} added` });
      });
    },
    managePaymentMethods: () => {
      dispatch({ type: "MANAGE_PAYMENT_METHODS" });
      scrollToSettingsSection("payment-methods");
    },
    manageStatsDefaults: () => {
      dispatch({ type: "OPEN_SETTINGS" });
      scrollToSettingsSection("stats-defaults");
    },
    addPaymentMethod: (input) => {
      const name = input.name.trim(); if (!name || getState().paymentMethods.some((m) => m.name.toLowerCase() === name.toLowerCase())) return;
      const entity: PaymentMethodEntity = { id: crypto.randomUUID(), name, type: input.type, detail: input.detail.trim(), archived: false };
      persist(saveEntity("paymentMethod", entity), () => dispatch({ type: "SHOW_TOAST", message: `${name} added` }));
    },
    editPaymentMethod: (id, input) => {
      const current = getState().paymentMethods.find((m) => m.id === id); if (!current || !input.name.trim()) return;
      persist(saveEntity("paymentMethod", { id, name: input.name.trim(), type: input.type, detail: input.detail.trim(), archived: current.archived }), () => dispatch({ type: "SHOW_TOAST", message: `${input.name.trim()} updated` }));
    },
    setDefaultPaymentMethod: (id) => persist(saveEntity("preferences", preferencesFrom(getState(), { defaultPaymentMethodId: id })), () => dispatch({ type: "SHOW_TOAST", message: "Default payment method updated" })),
    setPaymentMethodArchived: (id, archived) => {
      const state = getState(); const current = state.paymentMethods.find((m) => m.id === id); if (!current) return;
      const active = state.paymentMethods.filter((m) => !m.archived); if (archived && active.length <= 1) { dispatch({ type: "SHOW_TOAST", message: "Keep at least one active payment method" }); return; }
      const tasks: Promise<unknown>[] = [saveEntity("paymentMethod", { id, name: current.name, type: current.type, detail: current.detail, archived })];
      if (archived && current.isDefault) tasks.push(saveEntity("preferences", preferencesFrom(state, { defaultPaymentMethodId: active.find((m) => m.id !== id)?.id ?? CASH_PAYMENT_METHOD.id })));
      persist(Promise.all(tasks), () => dispatch({ type: "SHOW_TOAST", message: archived ? `${current.name} archived` : `${current.name} restored` }));
    },
    saveTransactionEdits: (id, input) => {
      const state = getState(); const current = state.transactions.find((t) => t.id === id); const category = state.categories.find((c) => c.name === input.category); const method = state.paymentMethods.find((m) => paymentMethodLabel(m) === input.paymentMethod);
      if (!current || !category) return;
      const converted = convertEntry(input.amount, input.currency, state.currency, state.rates);
      if (!converted) { dispatch({ type: "SHOW_TOAST", message: "Exchange rates unavailable — try again once online" }); return; }
      persist(saveEntity("transaction", { id, name: input.name, ...converted, occurredAt: input.occurredAt, categoryId: category.id, paymentMethodId: method?.id ?? null }), () => { dispatch({ type: "CLOSE_DETAIL" }); dispatch({ type: "SHOW_TOAST", message: "Transaction updated" }); });
    },
    setRecurringName: (name) => dispatch({ type: "SET_RECURRING_NAME", name }), setRecurringAmount: (amount) => dispatch({ type: "SET_RECURRING_AMOUNT", amount }),
    setRecurringAnchorDate: (anchorDate) => dispatch({ type: "SET_RECURRING_ANCHOR_DATE", anchorDate }), setRecurringDay: (anchorDate) => dispatch({ type: "SET_RECURRING_ANCHOR_DATE", anchorDate }),
    setRecurringFrequency: (frequency) => dispatch({ type: "SET_RECURRING_FREQUENCY", frequency }), setRecurringCategory: (category) => dispatch({ type: "SET_RECURRING_CATEGORY", category }),
    setRecurringPaymentMethod: (paymentMethod) => dispatch({ type: "SET_RECURRING_PAYMENT_METHOD", paymentMethod }),
    saveRecurringEdits: (id, input) => {
      const state = getState(); const current = state.recurring.find((item) => item.id === id);
      const category = state.categories.find((c) => c.name === input.category);
      const method = state.paymentMethods.find((m) => paymentMethodLabel(m) === input.paymentMethod);
      if (!current || !category || !(input.amount > 0) || !input.name.trim() || input.anchorDate < localDateKey(new Date())) return;
      const entity: RecurringEntity = {
        id, name: input.name.trim(),
        ...recurringEntryFields(input.amount, input.currency),
        categoryId: category.id, paymentMethodId: method?.id ?? null,
        frequency: input.frequency.toLowerCase() as "monthly" | "yearly",
        anchorDate: input.anchorDate, paused: current.paused,
      };
      persist(saveEntity("recurring", entity), () => {
        dispatch({ type: "CLOSE_OVERLAY" }); dispatch({ type: "SHOW_TOAST", message: `${entity.name} updated` });
      });
    },
    saveRecurring: () => {
      const state = getState();
      const draft = state.recurringDraft;
      const category = state.categories.find((c) => c.name === draft.category);
      const method = state.paymentMethods.find((m) => paymentMethodLabel(m) === draft.paymentMethod);
      const amount = Number(draft.amount);
      if (!category || !(amount > 0) || !/^\d{4}-\d{2}-\d{2}$/.test(draft.anchorDate)) return;

      if (draft.id) {
        const current = state.recurring.find((item) => item.id === draft.id);
        if (!current?.categoryId) return;
        if (draft.anchorDate < localDateKey(new Date())) return;
        const entity: RecurringEntity = {
          id: draft.id,
          name: draft.name.trim(),
          // This editor has no currency picker; preserve whatever currency the
          // bill was created with (the draft amount is shown in that currency).
          ...recurringEntryFields(
            amount,
            (current.currency ?? state.currency) as EnterableCurrency,
          ),
          categoryId: category.id,
          paymentMethodId: method?.id ?? null,
          frequency: draft.frequency.toLowerCase() as "monthly" | "yearly",
          anchorDate: draft.anchorDate,
          paused: current.paused,
        };
        persist(saveEntity("recurring", entity), () => {
          dispatch({ type: "CLOSE_OVERLAY" });
          dispatch({ type: "SHOW_TOAST", message: `${entity.name} updated` });
        });
        return;
      }

      const entity: RecurringEntity = {
        id: crypto.randomUUID(),
        name: draft.name.trim(),
        ...recurringEntryFields(amount, state.currency),
        categoryId: category.id,
        paymentMethodId: method?.id ?? null,
        frequency: draft.frequency.toLowerCase() as "monthly" | "yearly",
        anchorDate: draft.anchorDate,
        paused: false,
      };
      const backfill = occurrencesThrough({
        anchorDate: entity.anchorDate,
        frequency: entity.frequency,
      }).map((date) => {
        const tx: TransactionEntity = {
          id: crypto.randomUUID(),
          name: entity.name,
          amountMinor: entity.amountMinor,
          occurredAt: occurrenceTimestamp(date),
          categoryId: entity.categoryId,
          paymentMethodId: entity.paymentMethodId,
        };
        return saveEntity("transaction", tx);
      });
      persist(Promise.all([saveEntity("recurring", entity), ...backfill]), () => {
        dispatch({ type: "CLOSE_OVERLAY" });
        dispatch({
          type: "SHOW_TOAST",
          message:
            backfill.length > 0
              ? `${entity.name} added · ${backfill.length} transaction${backfill.length === 1 ? "" : "s"}`
              : `${entity.name} added`,
        });
      });
    },
    deleteRecurring: () => {
      const state = getState();
      const id = state.recurringDraft.id;
      if (!id) return;
      const current = state.recurring.find((item) => item.id === id);
      if (!current) return;
      persist(removeEntity("recurring", id), () => {
        dispatch({ type: "CLOSE_OVERLAY" });
        dispatch({ type: "SHOW_TOAST", message: `${current.name} deleted` });
      });
    },
    setCategoryName: (name) => dispatch({ type: "SET_CATEGORY_NAME", name }),
    setCategoryEmoji: (emoji) => dispatch({ type: "SET_CATEGORY_EMOJI", emoji }),
    setCategoryLimit: (limit) => dispatch({ type: "SET_CATEGORY_LIMIT", limit }),
    openEditCategory: (id) => dispatch({ type: "OPEN_EDIT_CATEGORY", id }),
    saveCategory: () => {
      const state = getState();
      const name = state.categoryDraft.name.trim();
      if (!name) return;
      const emoji = state.categoryDraft.emoji || DEFAULT_CATEGORY_EMOJI;
      const amount = Number(state.categoryDraft.limit);
      const monthlyBudgetMinor = amount > 0 ? Math.round(amount * 100) : null;
      const editingId = state.categoryDraft.id;

      if (editingId) {
        const current = state.categories.find((c) => c.id === editingId);
        if (!current) return;
        const duplicate = state.categories.some(
          (c) => c.id !== editingId && c.name.toLowerCase() === name.toLowerCase(),
        );
        if (duplicate) return;
        const entity: CategoryEntity = {
          ...current,
          name,
          emoji,
          monthlyBudgetMinor,
        };
        persist(saveEntity("category", entity), () => {
          dispatch({ type: "CLOSE_OVERLAY" });
          dispatch({ type: "SHOW_TOAST", message: `${name} updated` });
        });
        return;
      }

      if (state.categories.some((c) => c.name.toLowerCase() === name.toLowerCase())) return;
      const entity: CategoryEntity = {
        id: crypto.randomUUID(),
        name,
        emoji,
        monthlyBudgetMinor,
        tint: "neutral",
        sortOrder: state.categories.length,
        system: false,
      };
      persist(saveEntity("category", entity), () => {
        dispatch({ type: "CLOSE_OVERLAY" });
        dispatch({ type: "SET_VIEW", view: "budgets" });
        dispatch({ type: "SHOW_TOAST", message: `${name} category added` });
      });
    },
    applySuggestedBudgets: (categoryIds) => {
      const state = getState();
      const selected = new Set(categoryIds);
      const updates = suggestedCategoryBudgetUpdates(state.transactions, state.categories)
        .filter((update) => selected.has(update.id));
      if (updates.length === 0) {
        dispatch({ type: "SHOW_TOAST", message: "No budgets selected" });
        return;
      }
      const byId = new Map(state.categories.map((category) => [category.id, category]));
      persist(
        saveEntities(
          updates.map((update) => {
            const current = byId.get(update.id);
            if (!current) throw new Error(`Missing category ${update.id}`);
            return {
              entityType: "category" as const,
              payload: {
                ...current,
                monthlyBudgetMinor: Math.round(update.suggestedLimit * 100),
              },
            };
          }),
        ),
        () => {
          dispatch({
            type: "SHOW_TOAST",
            message: updates.length === 1
              ? "Updated 1 budget from suggestions"
              : `Updated ${updates.length} budgets from suggestions`,
          });
        },
      );
    },
    deleteCategory: () => {
      const state = getState();
      const id = state.categoryDraft.id;
      if (!id) return;
      const category = state.categories.find((c) => c.id === id);
      if (!category) return;

      const tasks: Promise<unknown>[] = [
        removeEntity("category", id),
        ...state.transactions
          .filter((t) => t.categoryId === id)
          .map((t) => removeEntity("transaction", t.id)),
        ...state.recurring
          .filter((r) => r.categoryId === id)
          .map((r) => removeEntity("recurring", r.id)),
      ];
      persist(Promise.all(tasks), () => {
        dispatch({ type: "CLOSE_OVERLAY" });
        dispatch({ type: "SHOW_TOAST", message: `${category.name} deleted` });
      });
    },
    setProfileName: (name) => dispatch({ type: "SET_PROFILE_NAME", name }), setProfileEmail: (email) => dispatch({ type: "SET_PROFILE_EMAIL", email }),
    saveProfile: () => persist(saveEntity("preferences", preferencesFrom(getState())), () => dispatch({ type: "SHOW_TOAST", message: "Profile saved" })),
    setCurrency: (currency) => { dispatch({ type: "SET_CURRENCY", currency }); persist(saveEntity("preferences", preferencesFrom(getState(), { currency }))); },
    setWeekStart: (weekStart) => { dispatch({ type: "SET_WEEK_START", weekStart }); persist(saveEntity("preferences", preferencesFrom(getState(), { weekStart }))); },
    setTheme: (theme) => { dispatch({ type: "SET_THEME", theme }); persist(saveEntity("preferences", preferencesFrom(getState(), { theme }))); },
    setNavGlassOpacity: (opacity, options) => {
      const next = Math.min(100, Math.max(40, Math.round(opacity)));
      dispatch({ type: "SET_NAV_GLASS_OPACITY", opacity: next });
      if (options?.persist === false) return;
      persist(saveEntity("preferences", preferencesFrom(getState(), { navGlassOpacity: next })));
    },
    setDefaultStatsRange: (range) => {
      dispatch({ type: "SET_DEFAULT_STATS_RANGE", range });
      persist(
        saveEntity(
          "preferences",
          preferencesFrom(getState(), { defaultStatsRange: range }),
        ),
      );
    },
    toggleNotification: (key) => { const state = getState(); const notifications = { ...state.notifications, [key]: !state.notifications[key] }; dispatch({ type: "TOGGLE_NOTIFICATION", key }); persist(saveEntity("preferences", preferencesFrom(state, { notifications }))); },
    showToast: (message) => dispatch({ type: "SHOW_TOAST", message }), syncNow: () => { void requestFullSync(); },
  };
}

interface AppStoreValue { state: AppState; actions: AppActions; sync: SyncState; ready: boolean; }
const AppStoreContext = createContext<AppStoreValue | null>(null);

export function AppStoreProvider({
  children,
  user,
}: {
  children: ReactNode;
  user: { id: string; name: string; email: string; photoUrl: string | null };
}) {
  activateUserDatabase(user.id);
  const convex = useConvex();
  const [state, dispatch] = useReducer(reducer, user.name, createInitialState);
  const entities = useLiveQuery(() => db.entities.toArray(), [], undefined);
  const device = useLiveQuery(() => db.deviceMeta.get("device"), [], undefined);
  const meta = useLiveQuery(() => db.syncMeta.get(WORKSPACE_ID), [], undefined);
  const pending = useLiveQuery(() => db.outbox.where("status").equals("pending").count(), [], 0) ?? 0;
  const blocked = useLiveQuery(() => db.outbox.where("status").equals("blocked").count(), [], 0) ?? 0;

  // Keep the latest ECB rates in state for foreign-currency entry + "today's
  // value" display. Seed from local cache, then refresh from Convex (Frankfurter
  // is only hit once/day by the server cron).
  useEffect(() => {
    let cancelled = false;
    const cached = loadCachedRates();
    if (cached) dispatch({ type: "SET_RATES", rates: cached });
    const load = () => {
      void convex
        .query(latestRatesRef, {})
        .then((rates) => {
          if (cancelled || !rates) return;
          cacheRates(rates);
          dispatch({ type: "SET_RATES", rates });
        })
        .catch(() => {
          // Offline / auth — keep whatever cache we already seeded.
        });
    };
    load();
    window.addEventListener("focus", load);
    return () => {
      cancelled = true;
      window.removeEventListener("focus", load);
    };
  }, [convex]);

  useEffect(() => {
    let cancelled = false;
    void initializeLocalDatabase()
      .then(async () => {
        if (cancelled) return;
        const nextName = user.name.trim();
        const nextEmail = user.email.trim();

        // Pull before turning any bootstrap preference into a versioned local write.
        // Otherwise a fresh database created after sign-out can stamp the seeded 1Y
        // stats range with a newer version and overwrite the user's cloud preference.
        const coordinator = startSync(convex, {
          name: nextName || user.name,
          email: nextEmail || user.email,
        });
        await coordinator.request();
        if (cancelled) return;

        // Persist AuthKit profile into an established preferences row so later
        // preference pushes also carry name/email. A zero server revision means
        // initial sync did not complete, so leave the bootstrap row untouched.
        const existing = await db.entities.get(entityKey("preferences", "preferences"));
        if (!existing || existing.deleted || existing.serverRevision === 0) return;
        const current = existing.payload as PreferencesEntity;
        if (
          nextName &&
          nextEmail &&
          (current.profileName !== nextName || current.profileEmail !== nextEmail)
        ) {
          await saveEntity("preferences", {
            ...current,
            id: "preferences",
            profileName: nextName,
            profileEmail: nextEmail,
          });
        }
      })
      .catch((error) => {
        if (!cancelled) {
          dispatch({ type: "SHOW_TOAST", message: `Local database failed: ${String(error)}` });
        }
      });
    return () => {
      cancelled = true;
      stopSync();
    };
  }, [convex, user.name, user.email]);

  useEffect(() => {
    if (!entities?.length) return;
    const active = entities.filter((row) => !row.deleted);
    const categories = active
      .filter((r) => r.entityType === "category")
      .map((r) => {
        const payload = r.payload as CategoryEntity & { emoji?: string };
        return {
          ...payload,
          emoji: payload.emoji || DEFAULT_CATEGORY_EMOJI,
        } satisfies CategoryEntity;
      })
      .sort((a, b) => a.sortOrder - b.sortOrder);
    const storedPreference = active.find((r) => r.entityType === "preferences")?.payload as Partial<PreferencesEntity> | undefined;
    const preference: PreferencesEntity = { ...DEFAULT_PREFERENCES, ...storedPreference };
    const methodEntities = active.filter((r) => r.entityType === "paymentMethod").map((r) => r.payload as PaymentMethodEntity);
    const paymentMethods: PaymentMethodOption[] = methodEntities.map((m) => ({ ...m, isDefault: m.id === preference.defaultPaymentMethodId }));
    const categoryMap = new Map(categories.map((c) => [c.id, c])); const methodMap = new Map(paymentMethods.map((m) => [m.id, m]));
    const transactions = active.filter((r) => r.entityType === "transaction").map((r) => r.payload as TransactionEntity).sort((a, b) => b.occurredAt - a.occurredAt).map((t) => { const category = categoryMap.get(t.categoryId); const method = t.paymentMethodId ? methodMap.get(t.paymentMethodId) : undefined; const source = t.sourceCurrency ? { sourceCurrency: t.sourceCurrency as EnterableCurrency, sourceAmount: toMajorUnits(t.sourceAmountMinor ?? 0, t.sourceCurrency) } : {}; return { id: t.id, name: t.name, amount: t.amountMinor / 100, amountMinor: t.amountMinor, occurredAt: t.occurredAt, categoryId: t.categoryId, paymentMethodId: t.paymentMethodId, category: category?.name ?? "Unknown category", emoji: category?.emoji ?? DEFAULT_CATEGORY_EMOJI, paymentMethod: method ? paymentMethodLabel(method) : "Unknown method", time: formatTransactionTime(t.occurredAt), day: formatTransactionDay(t.occurredAt), green: category?.tint === "green", ...source }; });
    const recurring = active.filter((r) => r.entityType === "recurring").map((r) => r.payload as RecurringEntity).sort((a, b) => nextOccurrence(a).getTime() - nextOccurrence(b).getTime()).map((item) => { const category = categoryMap.get(item.categoryId); const dueDate = nextOccurrence(item); const days = Math.round((dueDate.getTime() - new Date().setHours(0, 0, 0, 0)) / 86_400_000); const currency = item.currency as EnterableCurrency | undefined; return { id: item.id, name: item.name, amount: toMajorUnits(item.amountMinor, currency ?? preference.currency), amountMinor: item.amountMinor, categoryId: item.categoryId, paymentMethodId: item.paymentMethodId, category: category?.name ?? "Unknown category", emoji: category?.emoji ?? DEFAULT_CATEGORY_EMOJI, due: recurringDueLabel(item), paused: item.paused, urgent: days <= 2, green: category?.tint === "green", anchorDate: item.anchorDate, frequency: item.frequency, ...(currency ? { currency } : {}) }; });
    const lends = active
      .filter((r) => r.entityType === "lend")
      .map((r) => r.payload as LendEntity)
      .sort((a, b) => b.occurredAt - a.occurredAt)
      .map((item) => ({
        id: item.id,
        contactName: item.contactName,
        contactId: item.contactId?.trim() || item.contactName,
        amount: item.amountMinor / 100,
        amountMinor: item.amountMinor,
        occurredAt: item.occurredAt,
        comment: item.comment,
        kind: item.kind === "repaid" ? "repaid" as const : "lent" as const,
        time: formatTransactionTime(item.occurredAt),
        day: formatTransactionDay(item.occurredAt),
      }));
    dispatch({ type: "HYDRATE_DATA", data: { transactions, recurring, lends, categories, limits: Object.fromEntries(categories.map((c) => [c.name, c.monthlyBudgetMinor === null ? null : c.monthlyBudgetMinor / 100])), paymentMethods, preferences: { ...preference, defaultView: preference.defaultView }, lastPaymentMethod: device?.lastPaymentMethodId && methodMap.get(device.lastPaymentMethodId) ? paymentMethodLabel(methodMap.get(device.lastPaymentMethodId)!) : null } });
  }, [entities, device]);

  useEffect(() => { if (!state.toast) return; const timer = setTimeout(() => dispatch({ type: "CLEAR_TOAST" }), TOAST_DURATION_MS); return () => clearTimeout(timer); }, [state.toast, state.toastNonce]);
  useLayoutEffect(() => {
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const apply = () => {
      document.documentElement.dataset.theme = state.theme;
      const resolved = state.theme === "system" ? (media.matches ? "dark" : "light") : state.theme;
      const canvas = resolved === "dark" ? "#0c1210" : "#f5f8f6";
      document.documentElement.style.colorScheme = resolved;
      // iOS home-screen PWAs color the status-bar band from theme-color + page bg.
      // Drop media-specific tags so OS dark mode can't force a black chrome over a light UI.
      document.querySelectorAll('meta[name="theme-color"]').forEach((el) => el.remove());
      const themeMeta = document.createElement("meta");
      themeMeta.name = "theme-color";
      themeMeta.content = canvas;
      document.head.appendChild(themeMeta);
      document.documentElement.style.backgroundColor = canvas;
      document.body.style.backgroundColor = canvas;
    };
    apply();
    if (state.theme !== "system") return;
    media.addEventListener("change", apply);
    return () => media.removeEventListener("change", apply);
  }, [state.theme]);
  const actions = useMemo(() => createActions(dispatch, () => state), [state]);
  const sync: SyncState = useMemo(() => ({ workspaceId: WORKSPACE_ID, lastPulledRevision: meta?.lastPulledRevision ?? 0, lastSyncedAt: meta?.lastSyncedAt ?? null, error: meta?.error ?? null, syncing: meta?.syncing ?? false, pending, blocked, configured: Boolean(process.env.NEXT_PUBLIC_CONVEX_URL) }), [meta, pending, blocked]);
  const value = useMemo(() => ({
    state: {
      ...state,
      profile: { name: user.name, email: user.email, photoUrl: user.photoUrl },
      defaultView: "home",
    },
    actions,
    sync,
    ready: state.dataReady,
  }), [state, actions, sync, user]);
  return <AppStoreContext.Provider value={value}>{children}</AppStoreContext.Provider>;
}

function useStore() { const store = useContext(AppStoreContext); if (!store) throw new Error("useStore must be used within an AppStoreProvider"); return store; }
export function useAppState() { return useStore().state; }
export function useAppActions() { return useStore().actions; }
export function useSyncState() { return useStore().sync; }
