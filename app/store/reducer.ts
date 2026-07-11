import { paymentMethodLabel, type Frequency, type Recurring, type Transaction } from "@/lib/types";
import { localDateKey, nextOccurrence } from "@/lib/dates";
import type { Action } from "@/store/actions";
import {
  AppState,
  EMPTY_CATEGORY_DRAFT,
  EMPTY_EXPENSE_DRAFT,
  EMPTY_RECURRING_DRAFT,
} from "@/store/state";

let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}${Date.now()}_${idCounter}`;
}

function withToast(state: AppState, message: string): AppState {
  return { ...state, toast: message, toastNonce: state.toastNonce + 1 };
}

function expenseDraftFor(state: AppState) {
  const active = state.paymentMethods.filter((method) => !method.archived);
  const activeLabels = active.map(paymentMethodLabel);
  const defaultMethod = active.find((method) => method.isDefault) ?? active[0];
  const paymentMethod =
    state.lastPaymentMethod && activeLabels.includes(state.lastPaymentMethod)
      ? state.lastPaymentMethod
      : defaultMethod
        ? paymentMethodLabel(defaultMethod)
        : EMPTY_EXPENSE_DRAFT.paymentMethod;
  return { ...EMPTY_EXPENSE_DRAFT, paymentMethod };
}

/** Append a keypad press to the amount string (mobile add-expense flow). */
function pressAmountKey(current: string, key: string): string {
  if (key === "⌫") return current.slice(0, -1);
  if (key === ".") {
    return current.includes(".") ? current : (current || "0") + ".";
  }
  // Cap significant digits to keep the display readable.
  if (current.replace(".", "").length < 7) return current + key;
  return current;
}

/** Sanitize a free-typed decimal amount (web add-expense input). */
function sanitizeDecimal(value: string): string {
  const cleaned = value.replace(/[^0-9.]/g, "");
  const parts = cleaned.split(".");
  if (parts.length > 2) return parts[0] + "." + parts.slice(1).join("");
  return cleaned;
}

export function reducer(state: AppState, action: Action): AppState {
  switch (action.type) {
    case "HYDRATE_DATA": {
      const categoryNames = new Set(action.data.categories.map((c) => c.name));
      const fallbackCategory = action.data.categories[0]?.name ?? "";
      const expenseCategory = categoryNames.has(state.expenseDraft.category)
        ? state.expenseDraft.category
        : fallbackCategory;
      const recurringCategory = categoryNames.has(state.recurringDraft.category)
        ? state.recurringDraft.category
        : fallbackCategory;
      const filter =
        state.filter === "All" || categoryNames.has(state.filter)
          ? state.filter
          : "All";
      return {
        ...state,
        ...action.data,
        dataReady: true,
        view: state.dataReady ? state.view : action.data.preferences.defaultView,
        filter,
        expenseDraft: { ...state.expenseDraft, category: expenseCategory },
        recurringDraft: { ...state.recurringDraft, category: recurringCategory },
        profile: {
          name: action.data.preferences.profileName,
          email: action.data.preferences.profileEmail,
        },
        currency: action.data.preferences.currency,
        weekStart: action.data.preferences.weekStart,
        defaultView: action.data.preferences.defaultView,
        notifications: action.data.preferences.notifications,
      };
    }
    case "SET_VIEW":
      return { ...state, view: action.view };

    case "SET_FILTER":
      return { ...state, filter: action.category };

    case "SET_QUERY":
      return { ...state, query: action.query };

    case "SET_STATS_RANGE":
      return { ...state, statsRange: action.range, selectedMonth: null };

    case "SET_SELECTED_MONTH":
      return { ...state, selectedMonth: action.month };

    case "TOGGLE_MERCHANTS":
      return { ...state, merchantsExpanded: !state.merchantsExpanded };

    case "OPEN_MERCHANT":
      return { ...state, view: "tx", query: action.name, filter: "All" };

    case "OPEN_OVERLAY": {
      switch (action.overlay) {
        case "add":
          return { ...state, overlay: "add", expenseDraft: expenseDraftFor(state) };
        case "recurring":
          return {
            ...state,
            overlay: "recurring",
            recurringDraft: EMPTY_RECURRING_DRAFT,
          };
        case "category":
          return {
            ...state,
            overlay: "category",
            categoryDraft: EMPTY_CATEGORY_DRAFT,
          };
      }
      return state;
    }

    case "MANAGE_PAYMENT_METHODS":
      return { ...state, overlay: null, detailId: null, view: "account" };

    case "CLOSE_OVERLAY":
      return { ...state, overlay: null };

    case "OPEN_DETAIL":
      return { ...state, detailId: action.id };

    case "CLOSE_DETAIL":
      return { ...state, detailId: null };

    case "DELETE_DETAIL": {
      const next = {
        ...state,
        transactions: state.transactions.filter((t) => t.id !== state.detailId),
        detailId: null,
      };
      return withToast(next, "Transaction deleted");
    }

    case "TOGGLE_RECURRING": {
      let toggled: Recurring | undefined;
      const recurring = state.recurring.map((r) => {
        if (r.id !== action.id) return r;
        toggled = { ...r, paused: !r.paused };
        return toggled;
      });
      if (!toggled) return state;
      const message = toggled.paused
        ? `${toggled.name} paused`
        : `${toggled.name} resumed`;
      return withToast({ ...state, recurring }, message);
    }

    // ----- Expense draft -----
    case "SET_EXPENSE_AMOUNT":
      return {
        ...state,
        expenseDraft: {
          ...state.expenseDraft,
          amount: sanitizeDecimal(action.amount),
        },
      };

    case "PRESS_AMOUNT_KEY":
      return {
        ...state,
        expenseDraft: {
          ...state.expenseDraft,
          amount: pressAmountKey(state.expenseDraft.amount, action.key),
        },
      };

    case "SET_EXPENSE_NAME":
      return {
        ...state,
        expenseDraft: { ...state.expenseDraft, name: action.name },
      };

    case "SET_EXPENSE_CATEGORY":
      return {
        ...state,
        expenseDraft: { ...state.expenseDraft, category: action.category },
      };

    case "SET_EXPENSE_PAYMENT_METHOD":
      return {
        ...state,
        expenseDraft: {
          ...state.expenseDraft,
          paymentMethod: action.paymentMethod,
        },
      };

    case "SAVE_EXPENSE": {
      const amount = parseFloat(state.expenseDraft.amount);
      if (!(amount > 0)) return state;
      const tx: Transaction = {
        id: nextId("t"),
        name: state.expenseDraft.name.trim() || "New expense",
        category: state.expenseDraft.category,
        time: "Just now",
        day: "Today",
        amount: Math.round(amount),
        paymentMethod: state.expenseDraft.paymentMethod,
        green: true,
      };
      return withToast(
        {
          ...state,
          transactions: [tx, ...state.transactions],
          overlay: null,
          view: "tx",
          filter: "All",
          query: "",
          lastPaymentMethod: state.expenseDraft.paymentMethod,
          expenseDraft: expenseDraftFor({
            ...state,
            lastPaymentMethod: state.expenseDraft.paymentMethod,
          }),
        },
        "Expense added",
      );
    }

    case "ADD_PAYMENT_METHOD": {
      const name = action.input.name.trim();
      if (!name) return state;
      const duplicate = state.paymentMethods.some(
        (method) => method.name.toLowerCase() === name.toLowerCase(),
      );
      if (duplicate) return withToast(state, "A payment method with that name exists");
      const hasActiveMethod = state.paymentMethods.some((method) => !method.archived);
      return withToast(
        {
          ...state,
          paymentMethods: [
            ...state.paymentMethods,
            {
              id: nextId("pm"),
              name,
              type: action.input.type,
              detail: action.input.detail.trim(),
              isDefault: !hasActiveMethod,
              archived: false,
            },
          ],
        },
        `${name} added`,
      );
    }

    case "EDIT_PAYMENT_METHOD": {
      const name = action.input.name.trim();
      if (!name) return state;
      const duplicate = state.paymentMethods.some(
        (method) =>
          method.id !== action.id &&
          method.name.toLowerCase() === name.toLowerCase(),
      );
      if (duplicate) return withToast(state, "A payment method with that name exists");
      const current = state.paymentMethods.find((method) => method.id === action.id);
      if (!current) return state;
      const previousLabel = paymentMethodLabel(current);
      const updated = {
        ...current,
        name,
        type: action.input.type,
        detail: action.input.detail.trim(),
      };
      const nextLabel = paymentMethodLabel(updated);
      return withToast(
        {
          ...state,
          paymentMethods: state.paymentMethods.map((method) =>
            method.id === action.id ? updated : method,
          ),
          lastPaymentMethod:
            state.lastPaymentMethod === previousLabel ? nextLabel : state.lastPaymentMethod,
          expenseDraft:
            state.expenseDraft.paymentMethod === previousLabel
              ? { ...state.expenseDraft, paymentMethod: nextLabel }
              : state.expenseDraft,
        },
        `${name} updated`,
      );
    }

    case "SET_DEFAULT_PAYMENT_METHOD": {
      const selected = state.paymentMethods.find(
        (method) => method.id === action.id && !method.archived,
      );
      if (!selected) return state;
      return withToast(
        {
          ...state,
          paymentMethods: state.paymentMethods.map((method) => ({
            ...method,
            isDefault: method.id === action.id,
          })),
        },
        `${selected.name} is now the default`,
      );
    }

    case "SET_PAYMENT_METHOD_ARCHIVED": {
      const selected = state.paymentMethods.find((method) => method.id === action.id);
      if (!selected || selected.archived === action.archived) return state;
      const activeCount = state.paymentMethods.filter((method) => !method.archived).length;
      if (action.archived && activeCount <= 1) {
        return withToast(state, "Keep at least one active payment method");
      }
      let paymentMethods = state.paymentMethods.map((method) =>
        method.id === action.id ? { ...method, archived: action.archived } : method,
      );
      if (action.archived && selected.isDefault) {
        const nextDefault = paymentMethods.find((method) => !method.archived);
        paymentMethods = paymentMethods.map((method) => ({
          ...method,
          isDefault: method.id === nextDefault?.id,
        }));
      }
      return withToast(
        { ...state, paymentMethods },
        action.archived ? `${selected.name} archived` : `${selected.name} restored`,
      );
    }

    case "SAVE_TRANSACTION_EDITS":
      return withToast(
        {
          ...state,
          transactions: state.transactions.map((transaction) =>
            transaction.id === action.id
              ? {
                  ...transaction,
                  name: action.input.name,
                  amount: action.input.amount,
                  category: action.input.category,
                  paymentMethod: action.input.paymentMethod,
                }
              : transaction,
          ),
          detailId: null,
        },
        "Transaction updated",
      );

    // ----- Recurring draft -----
    case "OPEN_EDIT_RECURRING": {
      const item = state.recurring.find((r) => r.id === action.id);
      if (!item?.anchorDate) return state;
      const frequency: Frequency =
        item.frequency === "yearly" ? "Yearly" : "Monthly";
      const dueDate = localDateKey(
        nextOccurrence({
          anchorDate: item.anchorDate,
          frequency: item.frequency ?? "monthly",
        }),
      );
      return {
        ...state,
        overlay: "recurring",
        recurringDraft: {
          id: item.id,
          name: item.name,
          amount: String(Math.round(item.amount)),
          anchorDate: dueDate,
          frequency,
          category: item.category,
        },
      };
    }

    case "SET_RECURRING_NAME":
      return {
        ...state,
        recurringDraft: { ...state.recurringDraft, name: action.name },
      };

    case "SET_RECURRING_AMOUNT":
      return {
        ...state,
        recurringDraft: {
          ...state.recurringDraft,
          amount: action.amount.replace(/[^0-9]/g, ""),
        },
      };

    case "SET_RECURRING_ANCHOR_DATE": {
      if (
        state.recurringDraft.id &&
        action.anchorDate &&
        action.anchorDate < localDateKey(new Date())
      ) {
        return state;
      }
      return {
        ...state,
        recurringDraft: {
          ...state.recurringDraft,
          anchorDate: action.anchorDate,
        },
      };
    }

    case "SET_RECURRING_FREQUENCY":
      return {
        ...state,
        recurringDraft: {
          ...state.recurringDraft,
          frequency: action.frequency,
        },
      };

    case "SET_RECURRING_CATEGORY":
      return {
        ...state,
        recurringDraft: { ...state.recurringDraft, category: action.category },
      };

    case "SAVE_RECURRING": {
      const draft = state.recurringDraft;
      const amount = parseInt(draft.amount.replace(/[^0-9]/g, ""), 10) || 0;
      const valid =
        draft.name.trim().length > 0 && amount > 0 && /^\d{4}-\d{2}-\d{2}$/.test(draft.anchorDate);
      if (!valid) return state;

      const freqWord = draft.frequency.toLowerCase();
      const due = `Due ${draft.anchorDate} · ${freqWord}`;
      const name = draft.name.trim();

      const rec: Recurring = {
        id: nextId("r"),
        name,
        category: draft.category,
        due,
        amount,
        paused: false,
        green: true,
        anchorDate: draft.anchorDate,
        frequency: freqWord as "monthly" | "yearly",
      };
      const tx: Transaction = {
        id: nextId("t"),
        name,
        category: draft.category,
        time: "Recurring · just added",
        day: "Today",
        amount,
        green: true,
      };

      return withToast(
        {
          ...state,
          recurring: [...state.recurring, rec],
          transactions: [tx, ...state.transactions],
          overlay: null,
          recurringDraft: EMPTY_RECURRING_DRAFT,
        },
        `${name} added`,
      );
    }

    // ----- Category draft -----
    case "OPEN_EDIT_CATEGORY": {
      const category = state.categories.find((c) => c.id === action.id);
      if (!category) return state;
      const limit =
        category.monthlyBudgetMinor == null
          ? ""
          : String(category.monthlyBudgetMinor / 100);
      return {
        ...state,
        overlay: "category",
        categoryDraft: { id: category.id, name: category.name, limit },
      };
    }

    case "SET_CATEGORY_NAME":
      return {
        ...state,
        categoryDraft: { ...state.categoryDraft, name: action.name },
      };

    case "SET_CATEGORY_LIMIT":
      return {
        ...state,
        categoryDraft: {
          ...state.categoryDraft,
          limit: action.limit.replace(/[^0-9]/g, ""),
        },
      };

    // ----- Account -----
    case "SET_PROFILE_NAME":
      return { ...state, profile: { ...state.profile, name: action.name } };

    case "SET_PROFILE_EMAIL":
      return { ...state, profile: { ...state.profile, email: action.email } };

    case "SET_CURRENCY":
      return { ...state, currency: action.currency };

    case "SET_WEEK_START":
      return { ...state, weekStart: action.weekStart };

    case "SET_DEFAULT_VIEW":
      return { ...state, defaultView: action.view };

    case "TOGGLE_NOTIFICATION":
      return {
        ...state,
        notifications: {
          ...state.notifications,
          [action.key]: !state.notifications[action.key],
        },
      };

    // ----- Toast -----
    case "SHOW_TOAST":
      return withToast(state, action.message);

    case "CLEAR_TOAST":
      return { ...state, toast: null };

    default:
      return state;
  }
}
