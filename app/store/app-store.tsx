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
import { useLiveQuery } from "dexie-react-hooks";
import { db, type SyncMetaRecord } from "@/data/db";
import {
  CASH_PAYMENT_METHOD,
  DEFAULT_PREFERENCES,
  WORKSPACE_ID,
  type CategoryEntity,
  type PaymentMethodEntity,
  type PreferencesEntity,
  type RecurringEntity,
  type TransactionEntity,
} from "@/data/model";
import {
  initializeLocalDatabase,
  removeEntity,
  saveEntity,
  setLastPaymentMethod,
} from "@/data/repository";
import { formatTransactionDay, formatTransactionTime, localDateKey, nextOccurrence, occurrenceTimestamp, occurrencesThrough, recurringDueLabel } from "@/lib/dates";
import {
  paymentMethodLabel,
  type CategoryName,
  type Currency,
  type Frequency,
  type ID,
  type NotificationSettings,
  type OverlayKey,
  type PaymentMethod,
  type PaymentMethodInput,
  type PaymentMethodOption,
  type StatsRange,
  type TransactionEditInput,
  type ViewKey,
  type WeekStart,
} from "@/lib/types";
import type { Action } from "@/store/actions";
import { reducer } from "@/store/reducer";
import { type AppState, createInitialState } from "@/store/state";
import { requestSync, startSync, stopSync } from "@/sync/coordinator";

const TOAST_DURATION_MS = 1800;

export interface AppActions {
  setView: (view: ViewKey) => void; openAccount: () => void; closeAccount: () => void;
  setFilter: (category: CategoryName | "All") => void; setQuery: (query: string) => void;
  setStatsRange: (range: StatsRange) => void; setSelectedMonth: (month: string) => void;
  toggleMerchants: () => void; openMerchant: (name: string) => void;
  openOverlay: (overlay: Exclude<OverlayKey, null>) => void; closeOverlay: () => void;
  openDetail: (id: ID) => void; closeDetail: () => void; deleteDetail: () => void;
  toggleRecurring: (id: ID) => void;
  openEditRecurring: (id: ID) => void;
  setExpenseAmount: (amount: string) => void; pressAmountKey: (key: string) => void;
  setExpenseName: (name: string) => void; setExpenseCategory: (category: CategoryName) => void;
  setExpensePaymentMethod: (paymentMethod: PaymentMethod) => void; saveExpense: () => void;
  managePaymentMethods: () => void; addPaymentMethod: (input: PaymentMethodInput) => void;
  editPaymentMethod: (id: ID, input: PaymentMethodInput) => void;
  setDefaultPaymentMethod: (id: ID) => void;
  setPaymentMethodArchived: (id: ID, archived: boolean) => void;
  saveTransactionEdits: (id: ID, input: TransactionEditInput) => void;
  setRecurringName: (name: string) => void; setRecurringAmount: (amount: string) => void;
  setRecurringAnchorDate: (date: string) => void; setRecurringDay: (day: string) => void;
  setRecurringFrequency: (frequency: Frequency) => void;
  setRecurringCategory: (category: CategoryName) => void; saveRecurring: () => void;
  deleteRecurring: () => void;
  setCategoryName: (name: string) => void; setCategoryLimit: (limit: string) => void;
  openEditCategory: (id: ID) => void;
  saveCategory: () => void; deleteCategory: () => void;
  setProfileName: (name: string) => void;
  setProfileEmail: (email: string) => void; saveProfile: () => void;
  setCurrency: (currency: Currency) => void; setWeekStart: (weekStart: WeekStart) => void;
  setDefaultView: (view: string) => void;
  toggleNotification: (key: keyof NotificationSettings) => void;
  showToast: (message: string) => void; syncNow: () => void;
}

export interface SyncState extends SyncMetaRecord {
  pending: number;
  blocked: number;
  configured: boolean;
}

const viewToLabel = (view: ViewKey) => view === "tx" ? "Activity" : view[0].toUpperCase() + view.slice(1);
const labelToView = (label: string): ViewKey => label === "Activity" ? "tx" :
  (["home", "stats", "recurring", "budgets", "account"].includes(label.toLowerCase())
    ? label.toLowerCase() as ViewKey : "home");

function preferencesFrom(state: AppState, patch: Partial<PreferencesEntity> = {}): PreferencesEntity {
  const defaultMethod = state.paymentMethods.find((method) => method.isDefault)?.id ?? CASH_PAYMENT_METHOD.id;
  return {
    ...DEFAULT_PREFERENCES,
    profileName: state.profile.name,
    profileEmail: state.profile.email,
    currency: state.currency,
    weekStart: state.weekStart,
    defaultView: labelToView(state.defaultView),
    notifications: state.notifications,
    defaultPaymentMethodId: defaultMethod,
    ...patch,
  };
}

function createActions(dispatch: Dispatch<Action>, getState: () => AppState): AppActions {
  const fail = (error: unknown) => dispatch({ type: "SHOW_TOAST", message: `Could not save locally: ${error instanceof Error ? error.message : String(error)}` });
  const persist = (work: Promise<unknown>, onSaved?: () => void) => void work.then(onSaved).catch(fail);
  return {
    setView: (view) => dispatch({ type: "SET_VIEW", view }),
    openAccount: () => dispatch({ type: "SET_VIEW", view: "account" }),
    closeAccount: () => dispatch({ type: "SET_VIEW", view: "home" }),
    setFilter: (category) => dispatch({ type: "SET_FILTER", category }), setQuery: (query) => dispatch({ type: "SET_QUERY", query }),
    setStatsRange: (range) => dispatch({ type: "SET_STATS_RANGE", range }), setSelectedMonth: (month) => dispatch({ type: "SET_SELECTED_MONTH", month }),
    toggleMerchants: () => dispatch({ type: "TOGGLE_MERCHANTS" }), openMerchant: (name) => dispatch({ type: "OPEN_MERCHANT", name }),
    openOverlay: (overlay) => dispatch({ type: "OPEN_OVERLAY", overlay }), closeOverlay: () => dispatch({ type: "CLOSE_OVERLAY" }),
    openDetail: (id) => dispatch({ type: "OPEN_DETAIL", id }), closeDetail: () => dispatch({ type: "CLOSE_DETAIL" }),
    deleteDetail: () => {
      const id = getState().detailId; if (!id) return;
      persist(removeEntity("transaction", id), () => { dispatch({ type: "CLOSE_DETAIL" }); dispatch({ type: "SHOW_TOAST", message: "Transaction deleted" }); });
    },
    toggleRecurring: (id) => {
      const row = getState().recurring.find((item) => item.id === id); if (!row?.anchorDate || !row.categoryId) return;
      const entity: RecurringEntity = { id, name: row.name, amountMinor: row.amountMinor ?? Math.round(row.amount * 100), categoryId: row.categoryId, paymentMethodId: row.paymentMethodId ?? null, frequency: row.frequency ?? "monthly", anchorDate: row.anchorDate, paused: !row.paused };
      persist(saveEntity("recurring", entity), () => {
        dispatch({ type: "CLOSE_OVERLAY" });
        dispatch({ type: "SHOW_TOAST", message: entity.paused ? `${entity.name} paused` : `${entity.name} resumed` });
      });
    },
    openEditRecurring: (id) => dispatch({ type: "OPEN_EDIT_RECURRING", id }),
    setExpenseAmount: (amount) => dispatch({ type: "SET_EXPENSE_AMOUNT", amount }), pressAmountKey: (key) => dispatch({ type: "PRESS_AMOUNT_KEY", key }),
    setExpenseName: (name) => dispatch({ type: "SET_EXPENSE_NAME", name }), setExpenseCategory: (category) => dispatch({ type: "SET_EXPENSE_CATEGORY", category }),
    setExpensePaymentMethod: (paymentMethod) => dispatch({ type: "SET_EXPENSE_PAYMENT_METHOD", paymentMethod }),
    saveExpense: () => {
      const state = getState(); const amount = Number(state.expenseDraft.amount); const category = state.categories.find((c) => c.name === state.expenseDraft.category);
      const method = state.paymentMethods.find((m) => paymentMethodLabel(m) === state.expenseDraft.paymentMethod);
      if (!(amount > 0) || !category) return;
      const entity: TransactionEntity = { id: crypto.randomUUID(), name: state.expenseDraft.name.trim() || "New expense", amountMinor: Math.round(amount * 100), occurredAt: Date.now(), categoryId: category.id, paymentMethodId: method?.id ?? null };
      persist(Promise.all([saveEntity("transaction", entity), setLastPaymentMethod(method?.id ?? null)]), () => { dispatch({ type: "CLOSE_OVERLAY" }); dispatch({ type: "SET_VIEW", view: "tx" }); dispatch({ type: "SHOW_TOAST", message: "Expense added" }); });
    },
    managePaymentMethods: () => { dispatch({ type: "MANAGE_PAYMENT_METHODS" }); requestAnimationFrame(() => requestAnimationFrame(() => document.getElementById("payment-methods")?.scrollIntoView({ behavior: "smooth", block: "center" }))); },
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
      persist(saveEntity("transaction", { id, name: input.name, amountMinor: Math.round(input.amount * 100), occurredAt: current.occurredAt ?? Date.now(), categoryId: category.id, paymentMethodId: method?.id ?? null }), () => { dispatch({ type: "CLOSE_DETAIL" }); dispatch({ type: "SHOW_TOAST", message: "Transaction updated" }); });
    },
    setRecurringName: (name) => dispatch({ type: "SET_RECURRING_NAME", name }), setRecurringAmount: (amount) => dispatch({ type: "SET_RECURRING_AMOUNT", amount }),
    setRecurringAnchorDate: (anchorDate) => dispatch({ type: "SET_RECURRING_ANCHOR_DATE", anchorDate }), setRecurringDay: (anchorDate) => dispatch({ type: "SET_RECURRING_ANCHOR_DATE", anchorDate }),
    setRecurringFrequency: (frequency) => dispatch({ type: "SET_RECURRING_FREQUENCY", frequency }), setRecurringCategory: (category) => dispatch({ type: "SET_RECURRING_CATEGORY", category }),
    saveRecurring: () => {
      const state = getState();
      const draft = state.recurringDraft;
      const category = state.categories.find((c) => c.name === draft.category);
      const amount = Number(draft.amount);
      if (!category || !(amount > 0) || !/^\d{4}-\d{2}-\d{2}$/.test(draft.anchorDate)) return;

      if (draft.id) {
        const current = state.recurring.find((item) => item.id === draft.id);
        if (!current?.categoryId) return;
        if (draft.anchorDate < localDateKey(new Date())) return;
        const entity: RecurringEntity = {
          id: draft.id,
          name: draft.name.trim(),
          amountMinor: Math.round(amount * 100),
          categoryId: category.id,
          paymentMethodId: current.paymentMethodId ?? null,
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
        amountMinor: Math.round(amount * 100),
        categoryId: category.id,
        paymentMethodId: null,
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
          paymentMethodId: null,
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
    setCategoryName: (name) => dispatch({ type: "SET_CATEGORY_NAME", name }), setCategoryLimit: (limit) => dispatch({ type: "SET_CATEGORY_LIMIT", limit }),
    openEditCategory: (id) => dispatch({ type: "OPEN_EDIT_CATEGORY", id }),
    saveCategory: () => {
      const state = getState();
      const name = state.categoryDraft.name.trim();
      if (!name) return;
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
    setDefaultView: (view) => { dispatch({ type: "SET_DEFAULT_VIEW", view }); persist(saveEntity("preferences", preferencesFrom(getState(), { defaultView: labelToView(view) }))); },
    toggleNotification: (key) => { const state = getState(); const notifications = { ...state.notifications, [key]: !state.notifications[key] }; dispatch({ type: "TOGGLE_NOTIFICATION", key }); persist(saveEntity("preferences", preferencesFrom(state, { notifications }))); },
    showToast: (message) => dispatch({ type: "SHOW_TOAST", message }), syncNow: () => { void requestSync(); },
  };
}

interface AppStoreValue { state: AppState; actions: AppActions; sync: SyncState; ready: boolean; }
const AppStoreContext = createContext<AppStoreValue | null>(null);

export function AppStoreProvider({ children, userName }: { children: ReactNode; userName?: string }) {
  const [state, dispatch] = useReducer(reducer, userName, createInitialState);
  const entities = useLiveQuery(() => db.entities.toArray(), [], undefined);
  const device = useLiveQuery(() => db.deviceMeta.get("device"), [], undefined);
  const meta = useLiveQuery(() => db.syncMeta.get(WORKSPACE_ID), [], undefined);
  const pending = useLiveQuery(() => db.outbox.where("status").equals("pending").count(), [], 0) ?? 0;
  const blocked = useLiveQuery(() => db.outbox.where("status").equals("blocked").count(), [], 0) ?? 0;

  useEffect(() => { void initializeLocalDatabase().then(() => { startSync(); }).catch((error) => dispatch({ type: "SHOW_TOAST", message: `Local database failed: ${String(error)}` })); return () => stopSync(); }, []);

  useEffect(() => {
    if (!entities?.length) return;
    const active = entities.filter((row) => !row.deleted);
    const categories = active.filter((r) => r.entityType === "category").map((r) => r.payload as CategoryEntity).sort((a, b) => a.sortOrder - b.sortOrder);
    const preference = active.find((r) => r.entityType === "preferences")?.payload as PreferencesEntity | undefined ?? DEFAULT_PREFERENCES;
    const methodEntities = active.filter((r) => r.entityType === "paymentMethod").map((r) => r.payload as PaymentMethodEntity);
    const paymentMethods: PaymentMethodOption[] = methodEntities.map((m) => ({ ...m, isDefault: m.id === preference.defaultPaymentMethodId }));
    const categoryMap = new Map(categories.map((c) => [c.id, c])); const methodMap = new Map(paymentMethods.map((m) => [m.id, m]));
    const transactions = active.filter((r) => r.entityType === "transaction").map((r) => r.payload as TransactionEntity).sort((a, b) => b.occurredAt - a.occurredAt).map((t) => { const category = categoryMap.get(t.categoryId); const method = t.paymentMethodId ? methodMap.get(t.paymentMethodId) : undefined; return { id: t.id, name: t.name, amount: t.amountMinor / 100, amountMinor: t.amountMinor, occurredAt: t.occurredAt, categoryId: t.categoryId, paymentMethodId: t.paymentMethodId, category: category?.name ?? "Unknown category", paymentMethod: method ? paymentMethodLabel(method) : "Unknown method", time: formatTransactionTime(t.occurredAt), day: formatTransactionDay(t.occurredAt), green: category?.tint === "green" }; });
    const recurring = active.filter((r) => r.entityType === "recurring").map((r) => r.payload as RecurringEntity).sort((a, b) => nextOccurrence(a).getTime() - nextOccurrence(b).getTime()).map((item) => { const category = categoryMap.get(item.categoryId); const dueDate = nextOccurrence(item); const days = Math.round((dueDate.getTime() - new Date().setHours(0, 0, 0, 0)) / 86_400_000); return { id: item.id, name: item.name, amount: item.amountMinor / 100, amountMinor: item.amountMinor, categoryId: item.categoryId, paymentMethodId: item.paymentMethodId, category: category?.name ?? "Unknown category", due: recurringDueLabel(item), paused: item.paused, urgent: days <= 2, green: category?.tint === "green", anchorDate: item.anchorDate, frequency: item.frequency }; });
    dispatch({ type: "HYDRATE_DATA", data: { transactions, recurring, categories, limits: Object.fromEntries(categories.map((c) => [c.name, c.monthlyBudgetMinor === null ? null : c.monthlyBudgetMinor / 100])), paymentMethods, preferences: { ...preference, defaultView: preference.defaultView }, lastPaymentMethod: device?.lastPaymentMethodId && methodMap.get(device.lastPaymentMethodId) ? paymentMethodLabel(methodMap.get(device.lastPaymentMethodId)!) : null } });
  }, [entities, device]);

  useEffect(() => { if (!state.toast) return; const timer = setTimeout(() => dispatch({ type: "CLEAR_TOAST" }), TOAST_DURATION_MS); return () => clearTimeout(timer); }, [state.toast, state.toastNonce]);
  const actions = useMemo(() => createActions(dispatch, () => state), [state]);
  const sync: SyncState = useMemo(() => ({ workspaceId: WORKSPACE_ID, lastPulledRevision: meta?.lastPulledRevision ?? 0, lastSyncedAt: meta?.lastSyncedAt ?? null, error: meta?.error ?? null, syncing: meta?.syncing ?? false, pending, blocked, configured: Boolean(process.env.NEXT_PUBLIC_CONVEX_URL) }), [meta, pending, blocked]);
  const value = useMemo(() => ({ state: { ...state, defaultView: viewToLabel(labelToView(state.defaultView)) }, actions, sync, ready: state.dataReady }), [state, actions, sync]);
  return <AppStoreContext.Provider value={value}>{children}</AppStoreContext.Provider>;
}

function useStore() { const store = useContext(AppStoreContext); if (!store) throw new Error("useStore must be used within an AppStoreProvider"); return store; }
export function useAppState() { return useStore().state; }
export function useAppActions() { return useStore().actions; }
export function useSyncState() { return useStore().sync; }
