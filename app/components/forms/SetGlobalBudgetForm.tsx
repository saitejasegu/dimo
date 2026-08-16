"use client";

import { useMemo, useState } from "react";
import { globalBudgetAllocation } from "@/features/budgets/selectors";
import { currencySymbol, money } from "@/lib/format";
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

function digitsOnly(value: string, max = 15): string {
  return value.replace(/\D/g, "").slice(0, max);
}

function parseLimit(value: string | undefined): number | null {
  if (value == null || value.trim() === "") return null;
  if (!/^\d+$/.test(value.trim())) return null;
  const amount = Number(value.trim());
  if (!Number.isSafeInteger(amount) || amount <= 0) return null;
  return amount;
}

function wholeLimit(value: number | null | undefined): number | null {
  if (value == null || !Number.isFinite(value) || value <= 0) return null;
  const rounded = Math.round(value);
  return rounded > 0 ? rounded : null;
}

function fieldValue(limit: number | null): string {
  return limit != null && limit > 0 ? String(limit) : "";
}

function snapshotLimits(
  allocations: Array<{ id: string; allocatedLimit: number | null }>,
): Record<string, string> {
  return Object.fromEntries(
    allocations.map((item) => [item.id, fieldValue(item.allocatedLimit)]),
  );
}

function sumLimits(drafts: Record<string, string>): number {
  return Object.values(drafts).reduce((sum, value) => sum + (parseLimit(value) ?? 0), 0);
}

export function SetGlobalBudgetForm({ onDone }: { onDone: () => void }) {
  const { categories, transactions, currency } = useAppState();
  const { applyGlobalBudget } = useAppActions();
  const activeCategories = useMemo(
    () => categories.filter((category) => !category.archived),
    [categories],
  );
  const currentTotal = activeCategories.reduce(
    (sum, category) => sum + (category.monthlyBudgetMinor ?? 0) / 100,
    0,
  );
  const [amount, setAmount] = useState(() =>
    currentTotal > 0 ? String(Math.round(currentTotal)) : "",
  );
  const [initialAmount] = useState(amount);
  const [drafts, setDrafts] = useState<Record<string, string> | null>(null);
  const trimmedAmount = amount.trim();
  const validAmountText = /^\d+$/.test(trimmedAmount);
  const parsedAmount = validAmountText ? Number(trimmedAmount) : 0;
  const validAmount = Number.isSafeInteger(parsedAmount) && parsedAmount > 0;
  const allocation = useMemo(
    () => globalBudgetAllocation(transactions, activeCategories, validAmount ? parsedAmount : 0),
    [transactions, activeCategories, validAmount, parsedAmount],
  );
  const customizing = drafts != null;
  const proposing = !customizing && amount !== initialAmount;
  const displayedLimits = allocation.allocations.map((item) => ({
    id: item.id,
    currentLimit: item.currentLimit,
    allocatedLimit: customizing
      ? parseLimit(drafts[item.id])
      : proposing
        ? item.allocatedLimit
        : wholeLimit(item.currentLimit),
  }));
  const changedCount = displayedLimits.filter(
    (item) => item.currentLimit !== item.allocatedLimit,
  ).length;
  const canApply = activeCategories.length > 0
    && validAmount
    && changedCount > 0
    && (customizing || allocation.canApply);

  let message: string | null = null;
  if (activeCategories.length === 0) {
    message = "Create a category before setting a total budget.";
  } else if (proposing && allocation.issue === "no-history") {
    message = "No spending was found in the last 6 completed months. Enter amounts on each category below, or wait until there is enough history for a split.";
  } else if (trimmedAmount && !validAmount) {
    message = "Enter a whole monthly amount greater than zero.";
  } else if ((proposing || customizing) && validAmount && changedCount === 0) {
    message = "Your category budgets already match these amounts.";
  }

  function handleTotalChange(next: string) {
    setAmount(digitsOnly(next));
    setDrafts(null);
  }

  function handleCategoryChange(id: string, next: string) {
    const value = digitsOnly(next);
    const snapshot = drafts ?? snapshotLimits(displayedLimits);
    const updated = { ...snapshot, [id]: value };
    setDrafts(updated);
    const total = sumLimits(updated);
    setAmount(total > 0 ? String(total) : "");
  }

  return (
    <div>
      <p className="mb-4 text-[13px] leading-relaxed text-muted">
        Set one monthly total to split from spending in{" "}
        <span className="font-medium text-body">
          {lookbackLabel(allocation.window.start, allocation.window.end)}
        </span>
        , or edit any category — the total follows the sum.
      </p>

      <TextField
        label="Monthly total"
        value={amount}
        onChange={handleTotalChange}
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
          const category = activeCategories.find((candidate) => candidate.id === item.id);
          const hasHistory = item.sixMonthSpend > 0;
          const value = customizing
            ? (drafts[item.id] ?? "")
            : proposing
              ? fieldValue(item.allocatedLimit)
              : fieldValue(wholeLimit(item.currentLimit));
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
              <label className="shrink-0 text-right">
                <span className="flex items-center justify-end gap-1">
                  <span className="text-sm text-muted">{currencySymbol(currency)}</span>
                  <input
                    type="text"
                    inputMode="numeric"
                    value={value}
                    onChange={(event) => handleCategoryChange(item.id, event.target.value)}
                    placeholder="0"
                    aria-label={`${item.name} monthly budget`}
                    className="w-[5.75rem] rounded-lg border border-line bg-canvas px-2 py-1.5 text-right text-sm font-semibold text-ink outline-none placeholder:text-faint"
                  />
                </span>
                {hasHistory && proposing ? (
                  <span className="mt-0.5 block text-[10px] font-semibold uppercase tracking-[0.04em] text-green">
                    Proposed
                  </span>
                ) : (
                  <span className="mt-0.5 block text-[10px] font-semibold uppercase tracking-[0.04em] text-muted">
                    Budget
                  </span>
                )}
              </label>
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
        Changing the total proposes a new split. Editing a category updates the total to
        match. Apply replaces every category budget with the amounts shown here.
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
            applyGlobalBudget(displayedLimits.map((item) => ({
              id: item.id,
              allocatedLimit: item.allocatedLimit,
            })));
            onDone();
          }}
        >
          {(proposing || customizing) && validAmount && changedCount === 0
            ? "Already applied"
            : customizing
              ? "Apply budgets"
              : "Apply split"}
        </Button>
      </div>
    </div>
  );
}
