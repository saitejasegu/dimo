import {
  paymentMethodLabel,
  type Frequency,
  type PaymentMethod,
  type Recurring,
  type Transaction,
} from "@/lib/types";
import {
  formatTransactionDay,
  formatTransactionTime,
  localDateKey,
  localTimeKey,
  nextOccurrence,
} from "@/lib/dates";
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

function defaultPaymentMethodLabel(state: AppState): PaymentMethod {
  const active = state.paymentMethods.filter((method) => !method.archived);
  const defaultMethod = active.find((method) => method.isDefault) ?? active[0];
  return defaultMethod
    ? paymentMethodLabel(defaultMethod)
    : EMPTY_EXPENSE_DRAFT.paymentMethod;
}

function expenseDraftFor(state: AppState) {
  const active = state.paymentMethods.filter((method) => !method.archived);
  const activeLabels = active.map(paymentMethodLabel);
  const paymentMethod =
    state.lastPaymentMethod && activeLabels.includes(state.lastPaymentMethod)
      ? state.lastPaymentMethod
      : defaultPaymentMethodLabel(state);
  const now = new Date();
  return {
    ...EMPTY_EXPENSE_DRAFT,
    date: localDateKey(now),
    time: localTimeKey(now),
    paymentMethod,
  };
}

function recurringDraftFor(state: AppState) {
  return {
    ...EMPTY_RECURRING_DRAFT,
    paymentMethod: defaultPaymentMethodLabel(state),
  };
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
      const filter = state.filter.filter((category) => categoryNames.has(category));
      return {
        ...state,
        ...action.data,
        dataReady: true,
        view: state.dataReady ? state.view : "home",
        statsRange:
          !state.dataReady || state.statsRange === state.defaultStatsRange
            ? action.data.preferences.defaultStatsRange
            : state.statsRange,
        filter,
        expenseDraft: { ...state.expenseDraft, category: expenseCategory },
        recurringDraft: { ...state.recurringDraft, category: recurringCategory },
        profile: {
          name: action.data.preferences.profileName,
          email: action.data.preferences.profileEmail,
        },
        currency: action.data.preferences.currency,
        weekStart: action.data.preferences.weekStart,
        theme: action.data.preferences.theme ?? "light",
        navGlassOpacity: action.data.preferences.navGlassOpacity ?? 40,
        defaultView: "home",
        defaultStatsRange: action.data.preferences.defaultStatsRange,
        notifications: action.data.preferences.notifications,
      };
    }
    case "SET_VIEW": {
      const next = action.view === "tx" ? "home" : action.view;
      if (next === "account") {
        if (state.view === "account") return state;
        const from = state.view === "tx" ? "home" : state.view;
        return { ...state, view: "account", accountReturnView: from };
      }
      if (next === "settings") {
        if (state.view === "settings") return state;
        const current =
          state.view === "account"
            ? (state.accountReturnView ?? "home")
            : state.view === "tx"
              ? "home"
              : state.view;
        const from = current === "settings" ? "home" : current;
        return {
          ...state,
          view: "settings",
          accountReturnView: null,
          settingsReturnView: from,
        };
      }
      return {
        ...state,
        view: next,
        accountReturnView: null,
        settingsReturnView: null,
      };
    }
    case "OPEN_SETTINGS": {
      if (state.view === "settings") return state;
      const current =
        state.view === "account"
          ? (state.accountReturnView ?? "home")
          : state.view === "tx"
            ? "home"
            : state.view;
      const from = current === "settings" ? "home" : current;
      return {
        ...state,
        view: "settings",
        accountReturnView: null,
        settingsReturnView: from,
      };
    }
    case "CLOSE_SETTINGS":
      return {
        ...state,
        view: state.settingsReturnView ?? "home",
        accountReturnView: null,
        settingsReturnView: null,
      };
    case "OPEN_ACCOUNT": {
      if (state.view === "account") return state;
      const from = state.view === "tx" ? "home" : state.view;
      return { ...state, view: "account", accountReturnView: from };
    }
    case "CLOSE_ACCOUNT":
      return {
        ...state,
        view: state.accountReturnView ?? "home",
        accountReturnView: null,
      };

    case "SET_FILTER":
      if (action.category === "All") return { ...state, filter: [] };
      return {
        ...state,
        filter: state.filter.includes(action.category)
          ? state.filter.filter((category) => category !== action.category)
          : [...state.filter, action.category],
      };

    case "SET_PAYMENT_FILTER":
      return { ...state, paymentFilter: action.paymentMethod };

    case "SET_QUERY":
      return { ...state, query: action.query };

    case "SET_STATS_RANGE":
      return { ...state, statsRange: action.range, selectedMonth: null };

    case "SET_SELECTED_MONTH":
      return { ...state, selectedMonth: action.month };

    case "TOGGLE_MERCHANTS":
      return { ...state, merchantsExpanded: !state.merchantsExpanded };
    case "TOGGLE_CATEGORIES":
      return { ...state, categoriesExpanded: !state.categoriesExpanded };

    case "OPEN_MERCHANT":
      return {
        ...state,
        view: "home",
        query: action.name,
        filter: [],
        paymentFilter: "All",
      };

    case "OPEN_CATEGORY":
      return {
        ...state,
        view: "home",
        query: "",
        filter: [action.category],
        paymentFilter: "All",
      };

    case "OPEN_OVERLAY": {
      switch (action.overlay) {
        case "add":
          return { ...state, overlay: "add", expenseDraft: expenseDraftFor(state) };
        case "recurring":
          return {
            ...state,
            overlay: "recurring",
            recurringDraft: recurringDraftFor(state),
          };
        case "category":
          return {
            ...state,
            view: "budgets",
            accountReturnView: null,
            settingsReturnView: null,
            overlay: "category",
            categoryDraft: EMPTY_CATEGORY_DRAFT,
          };
      }
      return state;
    }

    case "MANAGE_PAYMENT_METHODS":
      return {
        ...state,
        overlay: null,
        detailId: null,
        view: "settings",
        accountReturnView: null,
        settingsReturnView:
          state.view === "settings"
            ? state.settingsReturnView
            : state.view === "account" || state.view === "tx"
              ? "home"
              : state.view,
      };

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

    case "SET_EXPENSE_DATE":
      return {
        ...state,
        expenseDraft: { ...state.expenseDraft, date: action.date },
      };

    case "SET_EXPENSE_TIME":
      return {
        ...state,
        expenseDraft: { ...state.expenseDraft, time: action.time },
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
          view: "home",
          filter: [],
          paymentFilter: "All",
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
          recurringDraft:
            state.recurringDraft.paymentMethod === previousLabel
              ? { ...state.recurringDraft, paymentMethod: nextLabel }
              : state.recurringDraft,
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
                  occurredAt: action.input.occurredAt,
                  time: formatTransactionTime(action.input.occurredAt),
                  day: formatTransactionDay(action.input.occurredAt),
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
      const method = item.paymentMethodId
        ? state.paymentMethods.find((m) => m.id === item.paymentMethodId)
        : undefined;
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
          paymentMethod: method
            ? paymentMethodLabel(method)
            : defaultPaymentMethodLabel(state),
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

    case "SET_RECURRING_PAYMENT_METHOD":
      return {
        ...state,
        recurringDraft: {
          ...state.recurringDraft,
          paymentMethod: action.paymentMethod,
        },
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
        paymentMethodId:
          state.paymentMethods.find(
            (m) => paymentMethodLabel(m) === draft.paymentMethod,
          )?.id ?? null,
      };
      const tx: Transaction = {
        id: nextId("t"),
        name,
        category: draft.category,
        time: "Recurring · just added",
        day: "Today",
        amount,
        green: true,
        paymentMethod: draft.paymentMethod,
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
        view: "budgets",
        accountReturnView: null,
        settingsReturnView: null,
        overlay: "category",
        categoryDraft: {
          id: category.id,
          name: category.name,
          emoji: category.emoji,
          limit,
        },
      };
    }

    case "SET_CATEGORY_NAME":
      return {
        ...state,
        categoryDraft: { ...state.categoryDraft, name: action.name },
      };

    case "SET_CATEGORY_EMOJI":
      return {
        ...state,
        categoryDraft: { ...state.categoryDraft, emoji: action.emoji },
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

    case "SET_THEME":
      return { ...state, theme: action.theme };

    case "SET_NAV_GLASS_OPACITY":
      return { ...state, navGlassOpacity: action.opacity };

    case "SET_DEFAULT_STATS_RANGE":
      return {
        ...state,
        defaultStatsRange: action.range,
        statsRange: action.range,
        selectedMonth: null,
      };

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
