"use client";

import { useEffect, useRef, useState } from "react";
import { cn } from "@/lib/cn";
import { currencySymbol } from "@/lib/format";
import {
  localDateKey,
  localDateTimeTimestamp,
  localTimeKey,
  nextOccurrence,
  recurringTransactionDates,
} from "@/lib/dates";
import {
  paymentMethodLabel,
  type Frequency,
  type PaymentMethod,
  type Recurring,
  type Transaction,
} from "@/lib/types";
import { useAppActions, useAppState } from "@/store/app-store";
import { categoryNames } from "@/features/transactions/selectors";
import { AmountKeypad } from "@/components/forms/AmountKeypad";
import { CategoryChips } from "@/components/forms/CategoryChips";
import { ExpenseDateTimeFields } from "@/components/forms/ExpenseDateTimeFields";
import { MerchantField } from "@/components/forms/MerchantField";
import { PaymentMethodSelect } from "@/components/forms/PaymentMethodSelect";
import { Button } from "@/components/ui/Button";
import { Checkbox } from "@/components/ui/Checkbox";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";

export type ExpenseEditorMode = "create" | "transaction" | "recurring";

function formatAmount(amount: number) {
  return amount % 1 === 0 ? String(amount) : amount.toFixed(2);
}

function nextAmount(current: string, key: string): string {
  if (key === "⌫") return current.slice(0, -1);
  if (key === ".") return current.includes(".") ? current : `${current || "0"}.`;
  const fractional = current.split(".")[1]?.length ?? 0;
  if (current.includes(".") && fractional >= 2) return current;
  return current.replace(".", "").length < 7 ? current + key : current;
}

function cleanAmount(value: string): string {
  const cleaned = value.replace(/[^0-9.]/g, "");
  const [whole = "", ...decimal] = cleaned.split(".");
  return decimal.length
    ? `${whole.slice(0, 7)}.${decimal.join("").slice(0, 2)}`
    : whole.slice(0, 7);
}

function FrequencySelect({
  value,
  onChange,
  disabled = false,
}: {
  value: Frequency;
  onChange: (value: Frequency) => void;
  disabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const closeOnOutsidePress = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    document.addEventListener("pointerdown", closeOnOutsidePress);
    document.addEventListener("keydown", closeOnEscape);
    return () => {
      document.removeEventListener("pointerdown", closeOnOutsidePress);
      document.removeEventListener("keydown", closeOnEscape);
    };
  }, [open]);

  return (
    <div ref={rootRef} className="relative min-w-[112px]">
      <button
        type="button"
        aria-label="Recurring frequency"
        aria-haspopup="listbox"
        aria-expanded={open}
        disabled={disabled}
        onClick={() => setOpen((current) => !current)}
        className={cn(
          "flex w-full items-center justify-between rounded-xl border border-line bg-surface px-3.5 py-2.5 text-sm font-medium text-ink transition-colors",
          open && "border-green ring-2 ring-green/10",
          disabled && "cursor-not-allowed bg-canvas-deep text-muted opacity-60",
        )}
      >
        <span>{value}</span>
        <span
          aria-hidden
          className={cn("ml-3 text-xs text-muted transition-transform", open && "rotate-180")}
        >
          ▾
        </span>
      </button>

      {open ? (
        <div
          role="listbox"
          aria-label="Recurring frequency"
          className="absolute right-0 top-full z-50 mt-2 min-w-full overflow-hidden rounded-xl border border-line bg-popup p-1.5 shadow-[0_16px_40px_rgba(0,0,0,0.28)]"
        >
          {(["Monthly", "Yearly"] as Frequency[]).map((option) => {
            const selected = option === value;
            return (
              <button
                key={option}
                type="button"
                role="option"
                aria-selected={selected}
                onClick={() => {
                  onChange(option);
                  setOpen(false);
                }}
                className={cn(
                  "flex w-full items-center justify-between rounded-lg px-3 py-2.5 text-left text-sm transition-colors",
                  selected
                    ? "bg-green-soft font-medium text-green-deep"
                    : "text-ink hover:bg-canvas focus:bg-canvas",
                )}
              >
                <span>{option}</span>
                {selected ? <span className="ml-3 text-green">✓</span> : null}
              </button>
            );
          })}
        </div>
      ) : null}
    </div>
  );
}

export function ExpenseEditorForm({
  mode,
  size,
  transaction,
  recurring,
  onCancel,
}: {
  mode: ExpenseEditorMode;
  size: "mobile" | "web";
  transaction?: Transaction;
  recurring?: Recurring;
  onCancel?: () => void;
}) {
  const {
    expenseDraft,
    currency,
    limits,
    paymentMethods,
    transactions,
    weekStart,
  } = useAppState();
  const actions = useAppActions();
  const now = new Date();
  const today = localDateKey(now);
  const defaultMethod =
    paymentMethods.find((method) => method.isDefault && !method.archived) ??
    paymentMethods.find((method) => !method.archived);
  const recordMethodId = transaction?.paymentMethodId ?? recurring?.paymentMethodId;
  const recordMethod = recordMethodId
    ? paymentMethods.find((method) => method.id === recordMethodId)
    : undefined;
  const initialPaymentMethod: PaymentMethod =
    recordMethod
      ? paymentMethodLabel(recordMethod)
      : transaction?.paymentMethod ?? expenseDraft.paymentMethod ?? (defaultMethod ? paymentMethodLabel(defaultMethod) : "Cash");
  const occurredAt = transaction?.occurredAt ? new Date(transaction.occurredAt) : now;
  const recurringDate = recurring?.anchorDate && recurring.frequency
    ? localDateKey(nextOccurrence({ anchorDate: recurring.anchorDate, frequency: recurring.frequency }))
    : today;

  const [amount, setAmount] = useState(
    mode === "create" ? expenseDraft.amount : formatAmount((transaction ?? recurring)?.amount ?? 0),
  );
  const [name, setName] = useState(
    mode === "create" ? expenseDraft.name : (transaction ?? recurring)?.name ?? "",
  );
  const [category, setCategory] = useState(
    mode === "create" ? expenseDraft.category : (transaction ?? recurring)?.category ?? "",
  );
  const [paymentMethod, setPaymentMethod] = useState(initialPaymentMethod);
  const [date, setDate] = useState(
    mode === "create"
      ? (expenseDraft.date || today)
      : mode === "transaction"
        ? localDateKey(occurredAt)
        : recurringDate,
  );
  const [time, setTime] = useState(
    mode === "create"
      ? (expenseDraft.time || localTimeKey(now))
      : mode === "transaction"
        ? localTimeKey(occurredAt)
        : localTimeKey(now),
  );
  const [isRecurring, setIsRecurring] = useState(mode === "recurring");
  const [frequency, setFrequency] = useState<Frequency>(
    recurring?.frequency === "yearly" ? "Yearly" : "Monthly",
  );
  const [backfillOpen, setBackfillOpen] = useState(false);

  const selectedArchived = paymentMethods.find(
    (method) => method.archived && paymentMethodLabel(method) === paymentMethod,
  );
  const availableMethods = [
    ...paymentMethods.filter((method) => !method.archived),
    ...(selectedArchived ? [selectedArchived] : []),
  ];
  const amountValue = Number(amount);
  const normalDateValid = isRecurring || date <= today;
  const valid =
    amountValue > 0 &&
    normalDateValid &&
    Boolean(category) &&
    (!isRecurring || (name.trim().length > 0 && /^\d{4}-\d{2}-\d{2}$/.test(date)));
  const mobile = size === "mobile";
  const originalRecurring = recurring
    ? {
        name: recurring.name,
        amount: formatAmount(recurring.amount),
        category: recurring.category,
        paymentMethod: initialPaymentMethod,
        date: recurringDate,
        frequency: recurring.frequency === "yearly" ? "Yearly" : "Monthly",
      }
    : null;
  const recurringDirty = Boolean(
    originalRecurring &&
      (name.trim() !== originalRecurring.name ||
        amount !== originalRecurring.amount ||
        category !== originalRecurring.category ||
        paymentMethod !== originalRecurring.paymentMethod ||
        date !== originalRecurring.date ||
        frequency !== originalRecurring.frequency),
  );

  function create(selection: "all" | "selected") {
    actions.saveExpense({
      name,
      amount: amountValue,
      category,
      paymentMethod,
      date,
      time,
      recurring: isRecurring,
      frequency,
      occurrenceSelection: selection,
    });
  }

  function save() {
    if (!valid) return;
    if (mode === "transaction" && transaction) {
      actions.saveTransactionEdits(transaction.id, {
        name: name.trim() || "New expense",
        amount: amountValue,
        category,
        paymentMethod,
        occurredAt: localDateTimeTimestamp(date, time),
      });
      return;
    }
    if (mode === "recurring" && recurring) {
      if (!recurringDirty) {
        actions.toggleRecurring(recurring.id);
      } else {
        actions.saveRecurringEdits(recurring.id, {
          name,
          amount: amountValue,
          category,
          paymentMethod,
          anchorDate: date,
          frequency,
        });
      }
      return;
    }
    if (isRecurring && date < today) {
      setBackfillOpen(true);
      return;
    }
    create("selected");
  }

  const plannedCount = isRecurring
    ? recurringTransactionDates(
        { anchorDate: date, frequency: frequency.toLowerCase() as "monthly" | "yearly" },
        "all",
      ).length
    : 0;
  const primaryLabel = mode === "recurring"
    ? recurringDirty
      ? "Save recurring"
      : recurring?.paused
        ? "Resume"
        : "Pause"
    : mode === "create" && isRecurring
      ? "Save recurring expense"
      : "Save expense";

  return (
    <div>
      <div
        className={cn(
          "mb-3.5",
          mobile
            ? "text-center font-display text-[40px] font-semibold"
            : "flex items-center gap-2.5 rounded-[14px] border border-line bg-canvas px-[18px] py-3.5",
          mobile && (amountValue > 0 ? "text-ink" : "text-disabled"),
        )}
      >
        <span className={cn(!mobile && "font-display text-[26px] font-semibold text-faint")}>
          {currencySymbol(currency)}
        </span>
        {mobile ? (
          amount || "0"
        ) : (
          <input
            value={amount}
            onChange={(event) => setAmount(cleanAmount(event.target.value))}
            placeholder="0"
            inputMode="decimal"
            autoComplete="off"
            autoFocus={mode === "create"}
            aria-label="Expense amount"
            className="w-full flex-1 bg-transparent font-display text-[32px] font-semibold text-ink outline-none placeholder:text-faint"
          />
        )}
      </div>

      <MerchantField
        value={name}
        onChange={setName}
        transactions={transactions}
        className="mb-3"
        onSelectSuggestion={(suggestion) => {
          setName(suggestion.name);
          setCategory(suggestion.category);
          if (suggestion.paymentMethod && availableMethods.some((method) => paymentMethodLabel(method) === suggestion.paymentMethod)) {
            setPaymentMethod(suggestion.paymentMethod);
          }
        }}
      />

      <div className="mb-4 grid grid-cols-2 items-start gap-3">
        <div className="min-w-0">
          <p className="mb-1.5 text-xs text-muted">Category</p>
          <CategoryChips
            selectedFirst
            categories={categoryNames(limits)}
            value={category}
            onChange={setCategory}
            menuClassName="left-0 right-auto w-[calc(200%+0.75rem)]"
          />
        </div>

        <PaymentMethodSelect
          value={paymentMethod}
          onChange={setPaymentMethod}
          methods={availableMethods}
          onManage={actions.managePaymentMethods}
          className="min-w-0"
          menuClassName="left-auto right-0 w-[calc(200%+0.75rem)]"
        />
      </div>

      <ExpenseDateTimeFields
        date={date}
        time={time}
        onDateChange={setDate}
        onTimeChange={setTime}
        weekStartsOn={weekStart === "Mon" ? 1 : 0}
        dateLabel={isRecurring ? (mode === "recurring" ? "Next due date" : "Start date") : "Date"}
        allowFuture={isRecurring}
        minDate={mode === "recurring" ? today : undefined}
        showTime={mode !== "recurring"}
        className="mb-4"
      />

      {mode !== "transaction" ? (
        <div className="mb-5 flex min-h-[50px] items-center justify-between gap-3 rounded-[14px] border border-line bg-canvas px-4 py-2.5">
          <Checkbox
            checked={isRecurring}
            onChange={setIsRecurring}
            label="Recurring"
            disabled={mode === "recurring"}
          />
          {isRecurring ? (
            <FrequencySelect
              value={frequency}
              onChange={setFrequency}
            />
          ) : null}
        </div>
      ) : null}

      {mobile ? (
        <div className="mb-4">
          <AmountKeypad onPress={(key) => setAmount((current) => nextAmount(current, key))} />
        </div>
      ) : null}

      <div className={cn(!mobile && "flex gap-3")}>
        {!mobile && onCancel ? (
          <Button variant="secondary" onClick={onCancel} className="shrink-0">Cancel</Button>
        ) : null}
        <Button onClick={save} enabled={valid} fullWidth={mobile} className={cn(!mobile && "flex-1")}>
          {primaryLabel}
        </Button>
      </div>

      <ConfirmDialog
        open={backfillOpen}
        title="Add previous transactions?"
        message={`This schedule has ${plannedCount} occurrence${plannedCount === 1 ? "" : "s"} through today.`}
        confirmLabel="Add all occurrences"
        alternateLabel="Add only this expense"
        cancelLabel="Cancel"
        tone="primary"
        onCancel={() => setBackfillOpen(false)}
        onConfirm={() => { setBackfillOpen(false); create("all"); }}
        onAlternate={() => { setBackfillOpen(false); create("selected"); }}
      />
    </div>
  );
}
