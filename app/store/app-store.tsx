"use client";

import {
  createContext,
  useContext,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  useSyncExternalStore,
  type Dispatch,
  type ReactNode,
} from "react";
import { useLiveQuery } from "dexie-react-hooks";
import { useConvex } from "convex/react";
import { makeFunctionReference } from "convex/server";
import { activateUserDatabase, db, EMPTY_PULLED_REVISIONS, type SyncMetaRecord } from "@/data/db";
import {
  CASH_PAYMENT_METHOD,
  DEFAULT_CATEGORY_EMOJI,
  DEFAULT_PREFERENCES,
  WORKSPACE_ID,
  payloadFromStored,
  type CategoryEntity,
  type PaymentMethodEntity,
  type PreferencesEntity,
  type RecurringEntity,
  type LendEntity,
  type TransactionEntity,
} from "@/data/model";
import {
  allStoredRows,
  getStoredRow,
  initializeLocalDatabase,
  removeEntities,
  removeEntity,
  saveEntity,
  saveEntities,
  setLastPaymentMethod,
} from "@/data/repository";
import { localDateKey, localDateTimeTimestamp, occurrenceTimestamp, occurrencesThrough, recurringTransactionDates } from "@/lib/dates";
import {
  paymentMethodIdForLabel,
  resolvePaymentMethodId,
  type CategoryName,
  type Currency,
  type ExpenseSaveInput,
  type Frequency,
  type ID,
  type LendKind,
  type LendSaveInput,
  type NotificationSettings,
  SHARED_LEND_CONTACT_PREFIX,
  type OverlayKey,
  type PaymentMethod,
  type PaymentMethodInput,
  type RecurringEditInput,
  type StatsRange,
  type ThemePreference,
  type TransactionEditInput,
  type ViewKey,
  type WeekStart,
} from "@/lib/types";
import type { Action } from "@/store/actions";
import { reducer } from "@/store/reducer";
import { projectEntities, type ProjectionSnapshot } from "@/store/projection";
import { useCoalesced } from "@/hooks/useCoalesced";
import { type AppState, createInitialState } from "@/store/state";
import { requestFullSync, startSync, stopSync } from "@/sync/coordinator";
import { LendingSharingProvider } from "@/store/lending-sharing";
import {
  categoryEmojiForName,
  defaultPaymentMethodIdForImport,
  type TransactionCsvRow,
} from "@/features/transactions/csv";
import {
  suggestedCategoryBudgetUpdates,
} from "@/features/budgets/selectors";
import { settlementLimit } from "@/features/lending/selectors";
import {
  cacheRates,
  convertMinor,
  loadCachedRates,
  rateBetween,
  recurringEntryFields,
  toMinorUnits,
  type RateTable,
} from "@/features/currency/rates";
import type { EnterableCurrency } from "@/lib/types";

const TOAST_DURATION_MS = 1800;

const LEND_NOUNS: Record<LendKind, string> = {
  lent: "Lend",
  repaid: "Repayment",
  borrowed: "Borrowing",
  returned: "Payment",
};

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
  setStatsPeriodOffset: (offset: number) => void;
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
  setCategoryArchived: (id: ID, archived: boolean) => void;
  applySuggestedBudgets: (categoryIds: string[]) => void;
  applyGlobalBudget: (
    limits: Array<{ id: string; allocatedLimit: number | null }>,
  ) => void;
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
  /** Returns false when the entry was rejected (e.g. a settlement over the balance). */
  saveLend: (input: LendSaveInput) => boolean;
  deleteLend: (id: ID) => void;
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
  "amountMinor" | "currency" | "sourceCurrency" | "sourceAmountMinor" | "exchangeRate"
>;

/**
 * Convert a major-unit `amount` entered in `currency` into a stored transaction
 * amount denominated in `defaultCurrency`. Always stamps `currency` with the
 * account default at write time so a later preferences change cannot reinterpret
 * historical `amountMinor` values. Returns `null` when a foreign amount cannot
 * be converted (rates unavailable).
 */
function convertEntry(
  amount: number,
  currency: EnterableCurrency,
  defaultCurrency: Currency,
  rates: AppState["rates"],
): TransactionCurrencyFields | null {
  const sourceMinor = Math.max(1, toMinorUnits(amount, currency));
  if (currency === defaultCurrency) {
    return { amountMinor: sourceMinor, currency: defaultCurrency };
  }
  const convertedMinor = convertMinor(sourceMinor, currency, defaultCurrency, rates);
  const ratio = rateBetween(currency, defaultCurrency, rates);
  if (convertedMinor == null || ratio == null) return null;
  return {
    amountMinor: Math.max(1, convertedMinor),
    currency: defaultCurrency,
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
    setStatsPeriodOffset: (offset) => dispatch({ type: "SET_STATS_PERIOD_OFFSET", offset }),
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
        removeEntities("transaction", unique),
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
        (async () => {
          await removeEntities("transaction", transactionIds);
          await removeEntities("recurring", recurringIds);
        })(),
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
            archived: false,
          };
          categoriesByName.set(key, category);
          newCategories.push(category);
        }
        transactions.push({
          id: crypto.randomUUID(), name: row.merchant, amountMinor: row.amountMinor,
          occurredAt: row.occurredAt, categoryId: category.id,
          paymentMethodId: defaultPaymentMethodId,
          currency: state.currency,
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
      const entity: RecurringEntity = { id, name: row.name, amountMinor: row.amountMinor ?? Math.round(row.amount * 100), categoryId: row.categoryId, paymentMethodId: resolvePaymentMethodId(row.paymentMethodId, state.paymentMethods), frequency: row.frequency ?? "monthly", anchorDate: row.anchorDate, paused: !row.paused, currency: row.currency ?? state.currency };
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
      const paymentMethodId = paymentMethodIdForLabel(input.paymentMethod, state.paymentMethods);
      if (!(input.amount > 0) || !category) return;
      const name = input.name.trim() || input.category;
      const currency = input.currency;

      if (!input.recurring) {
        const converted = convertEntry(input.amount, currency, state.currency, state.rates);
        if (!converted) { dispatch({ type: "SHOW_TOAST", message: "Exchange rates unavailable — try again once online" }); return; }
        const entity: TransactionEntity = {
          id: crypto.randomUUID(), name, ...converted,
          occurredAt: localDateTimeTimestamp(input.date, input.time),
          categoryId: category.id, paymentMethodId,
        };
        persist(Promise.all([saveEntity("transaction", entity), setLastPaymentMethod(paymentMethodId)]), () => {
          dispatch({ type: "CLOSE_OVERLAY" }); dispatch({ type: "SET_VIEW", view: "home" }); dispatch({ type: "SHOW_TOAST", message: "Expense added" });
        });
        return;
      }

      if (!input.name.trim() || !/^\d{4}-\d{2}-\d{2}$/.test(input.date)) return;
      const recurring: RecurringEntity = {
        id: crypto.randomUUID(), name: input.name.trim(),
        ...recurringEntryFields(input.amount, currency),
        categoryId: category.id, paymentMethodId,
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
      persist(Promise.all([saveEntities(entities), setLastPaymentMethod(paymentMethodId)]), () => {
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
      if (archived && id === CASH_PAYMENT_METHOD.id) {
        dispatch({ type: "SHOW_TOAST", message: "Cash can't be archived" });
        return;
      }
      const active = state.paymentMethods.filter((m) => !m.archived); if (archived && active.length <= 1) { dispatch({ type: "SHOW_TOAST", message: "Keep at least one active payment method" }); return; }
      const tasks: Promise<unknown>[] = [saveEntity("paymentMethod", { id, name: current.name, type: current.type, detail: current.detail, archived })];
      if (archived && current.isDefault) tasks.push(saveEntity("preferences", preferencesFrom(state, { defaultPaymentMethodId: active.find((m) => m.id !== id)?.id ?? CASH_PAYMENT_METHOD.id })));
      persist(Promise.all(tasks), () => dispatch({ type: "SHOW_TOAST", message: archived ? `${current.name} archived` : `${current.name} restored` }));
    },
    saveTransactionEdits: (id, input) => {
      const state = getState(); const current = state.transactions.find((t) => t.id === id); const category = state.categories.find((c) => c.name === input.category);
      if (!current || !category) return;
      const converted = convertEntry(input.amount, input.currency, state.currency, state.rates);
      if (!converted) { dispatch({ type: "SHOW_TOAST", message: "Exchange rates unavailable — try again once online" }); return; }
      const paymentMethodId = paymentMethodIdForLabel(input.paymentMethod, state.paymentMethods);
      persist(saveEntity("transaction", { id, name: input.name, ...converted, occurredAt: input.occurredAt, categoryId: category.id, paymentMethodId }), () => { dispatch({ type: "CLOSE_DETAIL" }); dispatch({ type: "SHOW_TOAST", message: "Transaction updated" }); });
    },
    setRecurringName: (name) => dispatch({ type: "SET_RECURRING_NAME", name }), setRecurringAmount: (amount) => dispatch({ type: "SET_RECURRING_AMOUNT", amount }),
    setRecurringAnchorDate: (anchorDate) => dispatch({ type: "SET_RECURRING_ANCHOR_DATE", anchorDate }), setRecurringDay: (anchorDate) => dispatch({ type: "SET_RECURRING_ANCHOR_DATE", anchorDate }),
    setRecurringFrequency: (frequency) => dispatch({ type: "SET_RECURRING_FREQUENCY", frequency }), setRecurringCategory: (category) => dispatch({ type: "SET_RECURRING_CATEGORY", category }),
    setRecurringPaymentMethod: (paymentMethod) => dispatch({ type: "SET_RECURRING_PAYMENT_METHOD", paymentMethod }),
    saveRecurringEdits: (id, input) => {
      const state = getState(); const current = state.recurring.find((item) => item.id === id);
      const category = state.categories.find((c) => c.name === input.category);
      if (!current || !category || !(input.amount > 0) || !input.name.trim() || input.anchorDate < localDateKey(new Date())) return;
      const entity: RecurringEntity = {
        id, name: input.name.trim(),
        ...recurringEntryFields(input.amount, input.currency),
        categoryId: category.id, paymentMethodId: paymentMethodIdForLabel(input.paymentMethod, state.paymentMethods),
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
      const paymentMethodId = paymentMethodIdForLabel(draft.paymentMethod, state.paymentMethods);
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
          paymentMethodId,
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
        paymentMethodId,
        frequency: draft.frequency.toLowerCase() as "monthly" | "yearly",
        anchorDate: draft.anchorDate,
        paused: false,
      };
      // One transaction for the bill and every backfilled occurrence (up to 1200):
      // saving them one at a time meant a write and a full re-projection per row.
      const backfill = occurrencesThrough({
        anchorDate: entity.anchorDate,
        frequency: entity.frequency,
      }).map((date) => ({
        entityType: "transaction" as const,
        payload: {
          id: crypto.randomUUID(),
          name: entity.name,
          amountMinor: entity.amountMinor,
          occurredAt: occurrenceTimestamp(date),
          categoryId: entity.categoryId,
          paymentMethodId: entity.paymentMethodId,
          currency: state.currency,
        } satisfies TransactionEntity,
      }));
      persist(
        saveEntities([{ entityType: "recurring", payload: entity }, ...backfill]),
        () => {
          dispatch({ type: "CLOSE_OVERLAY" });
          dispatch({
            type: "SHOW_TOAST",
            message:
              backfill.length > 0
                ? `${entity.name} added · ${backfill.length} transaction${backfill.length === 1 ? "" : "s"}`
                : `${entity.name} added`,
          });
        },
      );
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
        archived: false,
      };
      persist(saveEntity("category", entity), () => {
        dispatch({ type: "CLOSE_OVERLAY" });
        dispatch({ type: "SET_VIEW", view: "budgets" });
        dispatch({ type: "SHOW_TOAST", message: `${name} category added` });
      });
    },
    setCategoryArchived: (id, archived) => {
      const current = getState().categories.find((category) => category.id === id);
      if (!current || current.archived === archived) return;
      persist(saveEntity("category", { ...current, archived }), () => {
        dispatch({ type: "CLOSE_OVERLAY" });
        dispatch({
          type: "SHOW_TOAST",
          message: archived ? `${current.name} archived` : `${current.name} restored`,
        });
      });
    },
    applySuggestedBudgets: (categoryIds) => {
      const state = getState();
      const selected = new Set(categoryIds);
      const updates = suggestedCategoryBudgetUpdates(
        state.transactions,
        state.categories.filter((category) => !category.archived),
      )
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
    applyGlobalBudget: (limits) => {
      const state = getState();
      const active = state.categories.filter((category) => !category.archived);
      if (active.length === 0) {
        dispatch({
          type: "SHOW_TOAST",
          message: "Create a category before setting a total budget",
        });
        return;
      }

      const byId = new Map(active.map((category) => [category.id, category]));
      const updates = limits.flatMap((item) => {
        const current = byId.get(item.id);
        if (!current) return [];
        const monthlyBudgetMinor =
          item.allocatedLimit == null || item.allocatedLimit <= 0
            ? null
            : item.allocatedLimit * 100;
        if (current.monthlyBudgetMinor === monthlyBudgetMinor) return [];
        return [{
          entityType: "category" as const,
          payload: { ...current, monthlyBudgetMinor },
        }];
      });

      if (updates.length === 0) {
        dispatch({ type: "SHOW_TOAST", message: "Budgets already match this split" });
        return;
      }

      persist(saveEntities(updates), () => {
        dispatch({
          type: "SHOW_TOAST",
          message: updates.length === 1
            ? "Updated 1 budget from the total"
            : `Updated ${updates.length} budgets from the total`,
        });
      });
    },
    deleteCategory: () => {
      const state = getState();
      const id = state.categoryDraft.id;
      if (!id) return;
      const category = state.categories.find((c) => c.id === id);
      if (!category) return;

      persist(
        (async () => {
          await removeEntities(
            "transaction",
            state.transactions.filter((t) => t.categoryId === id).map((t) => t.id),
          );
          await removeEntities(
            "recurring",
            state.recurring.filter((r) => r.categoryId === id).map((r) => r.id),
          );
          await removeEntity("category", id);
        })(),
        () => {
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
    saveLend: (input) => {
      const state = getState();
      const existing = input.id ? state.lends.find((lend) => lend.id === input.id) : undefined;
      const contactName = input.contactName.trim();
      const contactId = input.contactId.trim() || existing?.contactId || "";
      if (!contactName || !contactId || !(input.amount > 0)) return false;
      // Editing never flips direction; the saved row's kind wins.
      const kind: LendKind = existing?.kind ?? input.kind;
      const limit = settlementLimit(kind, contactId, state.lends, existing?.id);
      if (limit !== null && input.amount > limit + 0.000_001) {
        dispatch({ type: "SHOW_TOAST", message: "That is more than the outstanding balance" });
        return false;
      }
      const shared = contactId.startsWith(SHARED_LEND_CONTACT_PREFIX);
      const entity: LendEntity = {
        id: existing?.id ?? `lend_${crypto.randomUUID()}`,
        contactName,
        contactId,
        amountMinor: Math.round(input.amount * 100),
        occurredAt: input.occurredAt,
        comment: input.comment.trim(),
        kind,
        // Shared ledgers can span accounts with different display currencies.
        currency: existing?.currency ?? state.currency,
        // The server assigns sharing metadata; mirror it so the row reads
        // correctly before the next pull.
        ...(shared
          ? {
              connectionId: contactId.slice(SHARED_LEND_CONTACT_PREFIX.length),
              createdBy: existing?.createdBy ?? "me",
              lastEditedBy: "me" as const,
            }
          : {
              ...(existing?.createdBy ? { createdBy: existing.createdBy } : {}),
              ...(existing?.lastEditedBy ? { lastEditedBy: existing.lastEditedBy } : {}),
            }),
      };
      const noun = LEND_NOUNS[kind];
      persist(saveEntity("lend", entity), () =>
        dispatch({ type: "SHOW_TOAST", message: existing ? `${noun} updated` : `${noun} saved` }),
      );
      return true;
    },
    deleteLend: (id) => {
      const kind = getState().lends.find((lend) => lend.id === id)?.kind ?? "lent";
      persist(removeEntity("lend", id), () =>
        dispatch({ type: "SHOW_TOAST", message: `${LEND_NOUNS[kind]} deleted` }),
      );
    },
  };
}

export interface AppUser {
  id: string;
  name: string;
  email: string;
  photoUrl: string | null;
}

/**
 * App state lives outside React so each consumer subscribes to just the fields it
 * reads. A single context meant every keystroke in a draft, every search character
 * and every toast re-rendered all ~40 consumers, including every mounted tab.
 */
class AppStateStore {
  private state: AppState;
  private user: AppUser;
  private profile: AppState["profile"];
  private published: AppState | null = null;
  private listeners = new Set<() => void>();

  constructor(initial: AppState, user: AppUser) {
    this.state = initial;
    this.user = user;
    this.profile = { name: user.name, email: user.email, photoUrl: user.photoUrl };
  }

  /** Raw reducer state, as actions have always read it. */
  getRaw = () => this.state;

  /** Reducer state with the signed-in identity applied, as screens see it. */
  getSnapshot = (): AppState => {
    this.published ??= { ...this.state, profile: this.profile, defaultView: "home" };
    return this.published;
  };

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  dispatch = (action: Action) => {
    const next = reducer(this.state, action);
    if (next === this.state) return;
    this.state = next;
    this.emit();
  };

  setUser(user: AppUser) {
    const current = this.user;
    if (
      current.name === user.name &&
      current.email === user.email &&
      current.photoUrl === user.photoUrl
    ) {
      return;
    }
    this.user = user;
    this.profile = { name: user.name, email: user.email, photoUrl: user.photoUrl };
    this.emit();
  }

  private emit() {
    this.published = null;
    for (const listener of this.listeners) listener();
  }
}

/**
 * Snapshot getter returning the same object until one of `fields` changes identity,
 * as `useSyncExternalStore` requires of a derived snapshot.
 */
function fieldSnapshot<K extends keyof AppState>(store: AppStateStore, fields: K[]) {
  let cached: { source: AppState; value: Pick<AppState, K> } | null = null;
  return () => {
    const source = store.getSnapshot();
    if (cached?.source === source) return cached.value;
    const previous = cached?.value;
    if (previous && fields.every((key) => previous[key] === source[key])) {
      cached = { source, value: previous };
      return previous;
    }
    const value = {} as Pick<AppState, K>;
    for (const key of fields) value[key] = source[key];
    cached = { source, value };
    return value;
  };
}

/** Subscribe to `keys` of the store; re-renders only when one of them changes identity. */
function useStoreFields<K extends keyof AppState>(
  store: AppStateStore,
  keys: readonly K[],
): Pick<AppState, K> {
  const signature = keys.join(",");
  const getSnapshot = useMemo(
    () => fieldSnapshot(store, signature.split(",") as K[]),
    [store, signature],
  );
  return useSyncExternalStore(store.subscribe, getSnapshot, getSnapshot);
}

/** Current local calendar day; changes at midnight and when the page regains focus. */
function useLocalDayKey() {
  const [dayKey, setDayKey] = useState(() => localDateKey(new Date()));
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout>;
    const refresh = () => setDayKey(localDateKey(new Date()));
    const arm = () => {
      const now = new Date();
      const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
      timer = setTimeout(() => {
        refresh();
        arm();
      }, midnight.getTime() - now.getTime() + 1000);
    };
    // Timers are throttled or frozen in background tabs, so re-check on return too.
    const visible = () => {
      if (document.visibilityState === "visible") refresh();
    };
    arm();
    document.addEventListener("visibilitychange", visible);
    return () => {
      clearTimeout(timer);
      document.removeEventListener("visibilitychange", visible);
    };
  }, []);
  return dayKey;
}

/** Rates change once a day on the server; don't re-query on every window focus. */
const RATES_REFRESH_INTERVAL_MS = 60 * 60 * 1000;

const AppStoreContext = createContext<AppStateStore | null>(null);
const AppActionsContext = createContext<AppActions | null>(null);
const SyncStateContext = createContext<SyncState | null>(null);

export function AppStoreProvider({
  children,
  user,
  authReady = true,
}: {
  children: ReactNode;
  user: AppUser;
  /**
   * False while a returning session is still being re-authenticated. Local data renders
   * immediately; anything that talks to Convex waits until this turns true.
   */
  authReady?: boolean;
}) {
  activateUserDatabase(user.id);
  const convex = useConvex();
  const [store] = useState(() => new AppStateStore(createInitialState(user.name), user));
  const { dispatch } = store;
  const { rates, theme, toast, toastNonce } = useStoreFields(store, [
    "rates",
    "theme",
    "toast",
    "toastNonce",
  ]);
  const dayKey = useLocalDayKey();
  // Previous projection, so unchanged entity types are reused rather than remapped.
  const snapshotRef = useRef<ProjectionSnapshot | null>(null);
  // Coalesced so a multi-page sync projects once instead of once per page.
  const liveEntities = useLiveQuery(() => allStoredRows(), [], undefined);
  const entities = useCoalesced(liveEntities);
  // Only this field of deviceMeta feeds the projection. Observing the whole row
  // re-ran the projection on every logical-clock bump, i.e. on every save.
  const lastPaymentMethodId = useLiveQuery(
    async () => (await db.deviceMeta.get("device"))?.lastPaymentMethodId ?? null,
    [],
    undefined,
  );
  const meta = useLiveQuery(() => db.syncMeta.get(WORKSPACE_ID), [], undefined);
  const pending = useLiveQuery(() => db.outbox.where("status").equals("pending").count(), [], 0) ?? 0;
  const blocked = useLiveQuery(() => db.outbox.where("status").equals("blocked").count(), [], 0) ?? 0;
  const [databaseReady, setDatabaseReady] = useState(false);

  useLayoutEffect(() => {
    store.setUser(user);
  }, [store, user]);

  // Seed the latest ECB rates from the local cache right away so foreign-currency
  // amounts render offline and before auth resolves.
  useEffect(() => {
    const cached = loadCachedRates();
    if (cached) dispatch({ type: "SET_RATES", rates: cached });
  }, [dispatch]);

  // Then refresh from Convex (Frankfurter is only hit once/day by the server cron).
  useEffect(() => {
    if (!authReady) return;
    let cancelled = false;
    let lastFetchedAt = 0;
    const load = () => {
      if (Date.now() - lastFetchedAt < RATES_REFRESH_INTERVAL_MS) return;
      void convex
        .query(latestRatesRef, {})
        .then((next) => {
          if (cancelled || !next) return;
          lastFetchedAt = Date.now();
          cacheRates(next);
          dispatch({ type: "SET_RATES", rates: next });
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
  }, [convex, authReady, dispatch]);

  useEffect(() => {
    let cancelled = false;
    void initializeLocalDatabase()
      .then(() => {
        if (!cancelled) setDatabaseReady(true);
      })
      .catch((error) => {
        if (!cancelled) {
          dispatch({ type: "SHOW_TOAST", message: `Local database failed: ${String(error)}` });
        }
      });
    return () => {
      cancelled = true;
    };
  }, [dispatch]);

  useEffect(() => {
    if (!databaseReady || !authReady) return;
    let cancelled = false;
    const nextName = user.name.trim();
    const nextEmail = user.email.trim();

    // Pull before turning any bootstrap preference into a versioned local write.
    // Otherwise a fresh database created after sign-out can stamp the seeded 1Y
    // stats range with a newer version and overwrite the user's cloud preference.
    const coordinator = startSync(convex, {
      name: nextName || user.name,
      email: nextEmail || user.email,
    });
    void coordinator
      .request()
      .then(async () => {
        if (cancelled) return;
        // Persist AuthKit profile into an established preferences row so later
        // preference pushes also carry name/email. A zero server revision means
        // initial sync did not complete, so leave the bootstrap row untouched.
        const existing = await getStoredRow("preferences", "preferences");
        if (!existing || existing.deleted || existing.serverRevision === 0) return;
        const current = payloadFromStored("preferences", existing);
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
  }, [convex, databaseReady, authReady, user.name, user.email, dispatch]);

  useEffect(() => {
    if (!entities?.length) return;
    const previous = snapshotRef.current;
    const snapshot = projectEntities(entities, {
      rates,
      lastPaymentMethodId,
      previous,
      dayKey,
    });
    // Nothing observable changed (e.g. an email-only write, or a re-emit of the same
    // rows) — skip the dispatch so no screen re-renders.
    if (!snapshot) return;
    snapshotRef.current = snapshot;
    dispatch({
      type: "HYDRATE_DATA",
      data: {
        transactions: snapshot.transactions,
        recurring: snapshot.recurring,
        lends: snapshot.lends,
        categories: snapshot.categories,
        limits: snapshot.limits,
        paymentMethods: snapshot.paymentMethods,
        preferences: snapshot.preferences,
        lastPaymentMethod: snapshot.lastPaymentMethod,
      },
    });
  }, [entities, lastPaymentMethodId, rates, dayKey, dispatch]);

  useEffect(() => { if (!toast) return; const timer = setTimeout(() => dispatch({ type: "CLEAR_TOAST" }), TOAST_DURATION_MS); return () => clearTimeout(timer); }, [toast, toastNonce, dispatch]);
  useLayoutEffect(() => {
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const apply = () => {
      document.documentElement.dataset.theme = theme;
      const resolved = theme === "system" ? (media.matches ? "dark" : "light") : theme;
      const canvas = resolved === "dark" ? "#0c1210" : "#f5f8f6";
      document.documentElement.style.colorScheme = resolved;
      // iOS home-screen PWAs color the status-bar band from theme-color + page bg.
      // Keep exactly one tag without a media query so OS dark mode can't force a
      // black chrome over a light UI; update it in place rather than re-creating it.
      const tags = document.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]');
      let themeMeta: HTMLMetaElement | null = null;
      tags.forEach((el) => {
        if (!themeMeta && !el.media) themeMeta = el;
        else el.remove();
      });
      if (!themeMeta) {
        themeMeta = document.createElement("meta");
        themeMeta.name = "theme-color";
        document.head.appendChild(themeMeta);
      }
      (themeMeta as HTMLMetaElement).content = canvas;
      document.documentElement.style.backgroundColor = canvas;
      document.body.style.backgroundColor = canvas;
    };
    apply();
    if (theme !== "system") return;
    media.addEventListener("change", apply);
    return () => media.removeEventListener("change", apply);
  }, [theme]);
  const actions = useMemo(() => createActions(store.dispatch, store.getRaw), [store]);
  const sync: SyncState = useMemo(() => ({
    workspaceId: WORKSPACE_ID,
    lastPulledRevision: meta?.lastPulledRevision ?? 0,
    pulledRevisions: meta?.pulledRevisions ?? { ...EMPTY_PULLED_REVISIONS },
    lastSyncedAt: meta?.lastSyncedAt ?? null,
    error: meta?.error ?? null,
    syncing: meta?.syncing ?? false,
    pending,
    blocked,
    configured: Boolean(process.env.NEXT_PUBLIC_CONVEX_URL),
  }), [meta, pending, blocked]);
  return (
    <AppStoreContext.Provider value={store}>
      <AppActionsContext.Provider value={actions}>
        <SyncStateContext.Provider value={sync}>
          <LendingSharingProvider>{children}</LendingSharingProvider>
        </SyncStateContext.Provider>
      </AppActionsContext.Provider>
    </AppStoreContext.Provider>
  );
}

/**
 * Read the named fields of app state. The component re-renders only when one of those
 * fields changes, so list exactly what the component uses.
 */
export function useAppState<K extends keyof AppState>(...keys: [K, ...K[]]): Pick<AppState, K> {
  const store = useContext(AppStoreContext);
  if (!store) throw new Error("useAppState must be used within an AppStoreProvider");
  return useStoreFields(store, keys);
}

export function useAppActions() {
  const actions = useContext(AppActionsContext);
  if (!actions) throw new Error("useAppActions must be used within an AppStoreProvider");
  return actions;
}

export function useSyncState() {
  const sync = useContext(SyncStateContext);
  if (!sync) throw new Error("useSyncState must be used within an AppStoreProvider");
  return sync;
}
