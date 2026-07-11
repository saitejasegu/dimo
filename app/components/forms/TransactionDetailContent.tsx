"use client";

import { useState } from "react";
import {
  paymentMethodLabel,
  type Currency,
  type Transaction,
} from "@/lib/types";
import { currencySymbol } from "@/lib/format";
import { cn } from "@/lib/cn";
import { useAppActions, useAppState } from "@/store/app-store";
import { categoryNames } from "@/features/transactions/selectors";
import { CategoryTint } from "@/components/ui/CategoryTint";
import { Button } from "@/components/ui/Button";
import { PaymentMethodSelect } from "@/components/forms/PaymentMethodSelect";

/** Shared transaction detail body used by the mobile sheet and web modal. */
export function TransactionDetailContent({
  transaction,
  currency,
  size = "mobile",
}: {
  transaction: Transaction;
  currency: Currency;
  size?: "mobile" | "web";
}) {
  const actions = useAppActions();
  const { paymentMethods, limits } = useAppState();
  const web = size === "web";
  const defaultMethod =
    paymentMethods.find((method) => method.isDefault && !method.archived) ??
    paymentMethods.find((method) => !method.archived);
  const currentPaymentMethod =
    transaction.paymentMethod ??
    (defaultMethod ? paymentMethodLabel(defaultMethod) : "Paid with");
  const selectedArchived = paymentMethods.find(
    (method) =>
      method.archived && paymentMethodLabel(method) === currentPaymentMethod,
  );
  const selectableMethods = [
    ...paymentMethods.filter((method) => !method.archived),
    ...(selectedArchived ? [selectedArchived] : []),
  ];
  const [amount, setAmount] = useState(String(transaction.amount));
  const [category, setCategory] = useState(transaction.category);
  const [paymentMethod, setPaymentMethod] = useState(currentPaymentMethod);
  const [categoryOpen, setCategoryOpen] = useState(false);
  const parsedAmount = Math.round(parseFloat(amount));
  const amountValid = Number.isFinite(parsedAmount) && parsedAmount > 0;
  const dirty =
    !amountValid ||
    parsedAmount !== transaction.amount ||
    category !== transaction.category ||
    paymentMethod !== currentPaymentMethod;

  const changeAmount = (value: string) => {
    const cleaned = value.replace(/[^0-9.]/g, "");
    const [rawWhole = "", ...decimal] = cleaned.split(".");
    const whole = rawWhole.slice(0, 7);
    setAmount(
      decimal.length ? `${whole}.${decimal.join("").slice(0, 2)}` : whole,
    );
  };

  const save = () => {
    if (!amountValid) return;
    actions.saveTransactionEdits(transaction.id, {
      amount: parsedAmount,
      category,
      paymentMethod,
    });
  };

  return (
    <div>
      <div className="mb-5 flex items-center gap-3.5">
        <CategoryTint
          green={transaction.green}
          size={web ? 52 : 48}
          radius={web ? 15 : 14}
        />
        <div className="flex-1">
          <div
            className={cn(
              "font-display font-semibold text-ink",
              web ? "text-[19px]" : "text-lg",
            )}
          >
            {transaction.name}
          </div>
          <div className="text-[13px] text-muted">
            {transaction.day} · {transaction.time}
          </div>
        </div>
        <label
          className={cn(
            "flex shrink-0 items-center border-b border-transparent font-display font-semibold text-ink transition-colors focus-within:border-green",
            web ? "text-2xl" : "text-[22px]",
          )}
        >
          <span aria-hidden="true">−{currencySymbol(currency)}</span>
          <input
            value={amount}
            onChange={(event) => changeAmount(event.target.value)}
            onFocus={(event) => event.currentTarget.select()}
            inputMode="decimal"
            aria-label="Transaction amount"
            className={cn(
              "min-w-0 bg-transparent text-right outline-none",
              web ? "w-[5.5rem]" : "w-[5rem]",
            )}
          />
        </label>
      </div>

      <div className="mb-5 rounded-2xl bg-canvas px-4">
        <div className="border-b border-line py-3">
          <button
            type="button"
            aria-expanded={categoryOpen}
            onClick={() => setCategoryOpen((open) => !open)}
            className="flex w-full items-center justify-between text-[13px]"
          >
            <span className="text-muted">Category</span>
            <span className="flex items-center gap-2 font-medium text-ink">
              {category}
              <span
                aria-hidden="true"
                className={cn(
                  "text-[10px] text-muted transition-transform",
                  categoryOpen && "rotate-180",
                )}
              >
                ▾
              </span>
            </span>
          </button>
          {categoryOpen ? (
            <div className="mt-3 flex flex-wrap gap-2">
              {categoryNames(limits).map((option) => (
                <button
                  key={option}
                  type="button"
                  onClick={() => {
                    setCategory(option);
                    setCategoryOpen(false);
                  }}
                  className={cn(
                    "rounded-full px-3 py-1.5 text-xs transition-colors",
                    option === category
                      ? "bg-ink font-medium text-white"
                      : "border border-line bg-surface text-body",
                  )}
                >
                  {option}
                </button>
              ))}
            </div>
          ) : null}
        </div>
        <PaymentMethodSelect
          value={paymentMethod}
          onChange={setPaymentMethod}
          methods={selectableMethods}
          onManage={actions.managePaymentMethods}
          className="py-3"
        />
      </div>

      <div className="flex gap-3">
        <Button variant="secondary" onClick={actions.closeDetail} className="flex-1">
          Close
        </Button>
        {dirty ? (
          <Button onClick={save} enabled={amountValid} className="flex-1">
            Save
          </Button>
        ) : (
          <Button variant="danger" onClick={actions.deleteDetail} className="flex-1">
            Delete
          </Button>
        )}
      </div>
    </div>
  );
}
