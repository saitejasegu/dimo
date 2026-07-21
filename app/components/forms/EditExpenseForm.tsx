"use client";

import { useState } from "react";
import {
  paymentMethodLabel,
  type EnterableCurrency,
  type PaymentMethod,
  type Transaction,
} from "@/lib/types";
import { currencySymbol } from "@/lib/format";
import { cn } from "@/lib/cn";
import { localDateKey, localDateTimeTimestamp, localTimeKey } from "@/lib/dates";
import { useAppActions, useAppState } from "@/store/app-store";
import { categoryNames } from "@/features/transactions/selectors";
import { AmountKeypad } from "@/components/forms/AmountKeypad";
import { CategoryChips } from "@/components/forms/CategoryChips";
import { ExpenseDateTimeFields } from "@/components/forms/ExpenseDateTimeFields";
import { PaymentMethodSelect } from "@/components/forms/PaymentMethodSelect";
import { Button } from "@/components/ui/Button";
import { DeleteIconButton } from "@/components/ui/DeleteIconButton";
import { TextField } from "@/components/ui/TextField";

function nextAmount(current: string, key: string): string {
  if (key === "⌫") return current.slice(0, -1);
  if (key === ".") return current.includes(".") ? current : `${current || "0"}.`;
  return current.replace(".", "").length < 7 ? current + key : current;
}

function cleanAmount(value: string): string {
  const cleaned = value.replace(/[^0-9.]/g, "");
  const [whole = "", ...decimal] = cleaned.split(".");
  return decimal.length
    ? `${whole.slice(0, 7)}.${decimal.join("").slice(0, 2)}`
    : whole.slice(0, 7);
}

export function EditExpenseForm({
  transaction,
  size,
}: {
  transaction: Transaction;
  size: "mobile" | "web";
}) {
  const { currency, limits, paymentMethods, weekStart } = useAppState();
  const actions = useAppActions();
  const defaultMethod =
    paymentMethods.find((method) => method.isDefault && !method.archived) ??
    paymentMethods.find((method) => !method.archived);
  const initialPaymentMethod =
    transaction.paymentMethod ??
    (defaultMethod ? paymentMethodLabel(defaultMethod) : "Cash");
  const selectedArchived = paymentMethods.find(
    (method) => method.archived && paymentMethodLabel(method) === initialPaymentMethod,
  );
  const availableMethods = [
    ...paymentMethods.filter((method) => !method.archived),
    ...(selectedArchived ? [selectedArchived] : []),
  ];

  const initialOccurred = new Date(transaction.occurredAt ?? 0);
  const entryCurrency = (transaction.sourceCurrency ??
    transaction.currency ??
    currency) as EnterableCurrency;
  const [amount, setAmount] = useState(
    String(transaction.sourceCurrency ? transaction.sourceAmount ?? transaction.amount : transaction.amount),
  );
  const [name, setName] = useState(transaction.name);
  const [category, setCategory] = useState(transaction.category);
  const [paymentMethod, setPaymentMethod] =
    useState<PaymentMethod>(initialPaymentMethod);
  const [date, setDate] = useState(localDateKey(initialOccurred));
  const [time, setTime] = useState(localTimeKey(initialOccurred));
  const amountValue = Math.round(parseFloat(amount));
  const valid = Number.isFinite(amountValue) && amountValue > 0;
  const mobile = size === "mobile";

  const save = () => {
    if (!valid) return;
    actions.saveTransactionEdits(transaction.id, {
      name: name.trim() || category,
      amount: amountValue,
      currency: entryCurrency,
      category,
      paymentMethod,
      occurredAt: localDateTimeTimestamp(date, time),
    });
  };

  return (
    <div>
      <div className="mb-4 flex items-center justify-between gap-4">
        <h2 className="font-display text-lg font-semibold text-ink">Edit expense</h2>
        <DeleteIconButton
          onClick={actions.deleteDetail}
          aria-label="Delete expense"
        />
      </div>

      {mobile ? (
        <div
          className={cn(
            "mb-3.5 text-center font-display text-[40px] font-semibold",
            valid ? "text-ink" : "text-disabled",
          )}
        >
          {currencySymbol(entryCurrency)}
          {amount || "0"}
        </div>
      ) : (
        <div className="mb-3.5 flex items-center gap-2.5 rounded-[14px] border border-line bg-canvas px-[18px] py-3.5">
          <span className="font-display text-[26px] font-semibold text-faint">
            {currencySymbol(entryCurrency)}
          </span>
          <input
            value={amount}
            onChange={(event) => setAmount(cleanAmount(event.target.value))}
            inputMode="decimal"
            aria-label="Expense amount"
            className="w-full flex-1 bg-transparent font-display text-[32px] font-semibold text-ink outline-none"
          />
        </div>
      )}

      <TextField
        value={name}
        onChange={setName}
        placeholder="Merchant (e.g. Chai Point)"
        className="mb-3"
      />

      {!mobile ? <p className="mb-2 text-xs text-muted">Category</p> : null}
      <CategoryChips
        categories={categoryNames(limits)}
        value={category}
        onChange={setCategory}
        className="mb-4"
      />

      <PaymentMethodSelect
        value={paymentMethod}
        onChange={setPaymentMethod}
        methods={availableMethods}
        onManage={actions.managePaymentMethods}
        className="mb-4"
      />

      <ExpenseDateTimeFields
        date={date}
        time={time}
        onDateChange={setDate}
        onTimeChange={setTime}
        weekStartsOn={weekStart === "Mon" ? 1 : 0}
        className="mb-4"
      />

      {mobile ? (
        <div className="mb-4">
          <AmountKeypad onPress={(key) => setAmount((current) => nextAmount(current, key))} />
        </div>
      ) : null}

      <div className={cn(!mobile && "flex gap-3")}>
        {!mobile ? (
          <Button variant="secondary" onClick={actions.closeDetail} className="shrink-0">
            Cancel
          </Button>
        ) : null}
        <Button onClick={save} enabled={valid} fullWidth={mobile} className={cn(!mobile && "flex-1")}>
          Save expense
        </Button>
      </div>
    </div>
  );
}
