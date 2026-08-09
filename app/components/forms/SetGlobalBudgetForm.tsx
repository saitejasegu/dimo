"use client";

import { useMemo, useState } from "react";
import { globalBudgetAllocation } from "@/features/budgets/selectors";
import { money } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { Button } from "@/components/ui/Button";
import { TextField } from "@/components/ui/TextField";

function lookbackLabel(start: number, end: number) {
  const first = new Date(start);
  const last = new Date(end);
  last.setMonth(last.getMonth() - 1);
  const month = new Intl.DateTimeFormat("en", { month: "short" });
  const monthYear = new Intl.DateTimeFormat("en", { month: "short", year: "numeric" });
  return first.getFullYear() === last.getFullYear()
    ? `${month.format(first)}–${monthYear.format(last)}`
    : `${monthYear.format(first)}–${monthYear.format(last)}`;
}

export function SetGlobalBudgetForm({ onDone }: { onDone: () => void }) {
  const { categories, transactions, currency } = useAppState();
  const { applyGlobalBudget } = useAppActions();
  const currentTotal = categories.reduce(
    (sum, category) => sum + (category.monthlyBudgetMinor ?? 0) / 100,
    0,
  );
  const [amount, setAmount] = useState(() =>
    currentTotal > 0 ? String(Math.round(currentTotal)) : "",
  );
  const trimmedAmount = amount.trim();
  const validAmountText = /^\d+$/.test(trimmedAmount);
  const parsedAmount = validAmountText ? Number(trimmedAmount) : 0;
  const validAmount = Number.isSafeInteger(parsedAmount) && parsedAmount > 0;
  const allocation = useMemo(
    () => globalBudgetAllocation(transactions, categories, validAmount ? parsedAmount : 0),
    [transactions, categories, validAmount, parsedAmount],
  );
  const changedCount = allocation.allocations.filter((item) => item.changed).length;
  const canApply = validAmount && allocation.canApply && changedCount > 0;

  let message: string | null = null;
  if (categories.length === 0) {
    message = "Create a category before setting a total budget.";
  } else if (allocation.issue === "no-history") {
    message = "No spending was found in the last 6 completed months. Set category budgets manually until there is enough history.";
  } else if (trimmedAmount && !validAmount) {
    message = "Enter a whole monthly amount greater than zero.";
  } else if (validAmount && changedCount === 0) {
    message = "Your category budgets already match this split.";
  }

  return (
    <div>
      <p className="mb-4 text-[13px] leading-relaxed text-muted">
        Set one monthly total and split it using average spending from{" "}
        <span className="font-medium text-body">
          {lookbackLabel(allocation.window.start, allocation.window.end)}
        </span>.
      </p>

      <TextField
        label="Monthly total"
        value={amount}
        onChange={setAmount}
        placeholder={`${currency} amount`}
        inputMode="numeric"
        autoFocus
      />

      {message ? (
        <p role="status" className="mt-2 text-xs leading-relaxed text-muted">
          {message}
        </p>
      ) : null}

      <div className="my-5 max-h-[46vh] overflow-y-auto overscroll-contain rounded-2xl border border-line">
        {allocation.allocations.map((item, index) => {
          const category = categories.find((candidate) => candidate.id === item.id);
          const hasHistory = item.sixMonthSpend > 0;
          return (
            <div
              key={item.id}
              className={`flex items-center gap-3 px-3.5 py-3.5 ${
                index > 0 ? "border-t border-line-soft" : ""
              }`}
            >
              <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-canvas-deep text-lg">
                {category?.emoji || "🙂"}
              </span>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm font-medium text-ink">
                  {item.name}
                </span>
                <span className="mt-0.5 block text-[11px] text-faint">
                  {hasHistory
                    ? `${money(item.monthlyAverage, currency)} monthly average · ${item.share}%`
                    : "No spending history · no allocation"}
                </span>
              </span>
              <span className="shrink-0 text-right">
                <span className={`block text-sm font-semibold ${hasHistory ? "text-ink" : "text-faint"}`}>
                  {hasHistory && validAmount && item.allocatedLimit != null
                    ? money(item.allocatedLimit, currency)
                    : "—"}
                </span>
                {hasHistory ? (
                  <span className="mt-0.5 block text-[10px] font-semibold uppercase tracking-[0.04em] text-green">
                    Proposed
                  </span>
                ) : null}
              </span>
            </div>
          );
        })}
        {allocation.allocations.length === 0 ? (
          <div className="px-4 py-8 text-center text-sm text-muted">
            No categories yet.
          </div>
        ) : null}
      </div>

      <p className="mb-5 rounded-xl bg-canvas-deep px-3.5 py-3 text-xs leading-relaxed text-muted">
        Applying this split replaces every category budget. You can still edit individual
        categories afterward; the total will follow their new sum.
      </p>

      <div className="flex gap-3">
        <Button variant="secondary" onClick={onDone} className="shrink-0">
          Cancel
        </Button>
        <Button
          className="flex-1"
          enabled={canApply}
          onClick={() => {
            if (!canApply) return;
            applyGlobalBudget(parsedAmount);
            onDone();
          }}
        >
          {validAmount && changedCount === 0 ? "Already applied" : "Apply split"}
        </Button>
      </div>
    </div>
  );
}
