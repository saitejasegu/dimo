"use client";

import { useEffect, useState } from "react";
import { money } from "@/lib/format";
import { cn } from "@/lib/cn";
import { useAppActions, useAppState } from "@/store/app-store";
import type { SuggestedCategoryBudgetUpdate } from "@/features/budgets/selectors";
import { Button } from "@/components/ui/Button";

export function ApplySuggestedBudgetsForm({
  updates,
  onDone,
}: {
  updates: SuggestedCategoryBudgetUpdate[];
  onDone: () => void;
}) {
  const { currency, categories } = useAppState();
  const { applySuggestedBudgets } = useAppActions();
  const [selected, setSelected] = useState<Set<string>>(
    () => new Set(updates.map((update) => update.id)),
  );

  useEffect(() => {
    setSelected(new Set(updates.map((update) => update.id)));
  }, [updates]);

  const emojiById = new Map(categories.map((category) => [category.id, category.emoji]));
  const selectedCount = selected.size;

  const toggle = (id: string) => {
    setSelected((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  return (
    <div>
      <p className="mb-4 text-[13px] leading-relaxed text-muted">
        Based on the last 6 months of spend. Choose which categories to update.
      </p>

      <div className="mb-5 max-h-[50vh] overflow-y-auto overscroll-contain rounded-2xl border border-line">
        {updates.map((update, index) => {
          const checked = selected.has(update.id);
          const emoji = emojiById.get(update.id);
          return (
            <button
              type="button"
              key={update.id}
              onClick={() => toggle(update.id)}
              className={cn(
                "flex w-full items-center gap-3 px-3.5 py-3.5 text-left transition-colors",
                index > 0 && "border-t border-line-soft",
                checked ? "bg-green-soft/40" : "bg-transparent hover:bg-canvas",
              )}
            >
              <span
                aria-hidden
                className={cn(
                  "flex h-5 w-5 shrink-0 items-center justify-center rounded-md border text-[11px] font-semibold",
                  checked
                    ? "border-green bg-green text-on-green"
                    : "border-line bg-canvas text-transparent",
                )}
              >
                ✓
              </span>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm font-medium text-ink">
                  {emoji ? `${emoji} ` : ""}
                  {update.name}
                </span>
                <span className="mt-0.5 block text-[11px] text-faint">
                  {update.currentLimit == null
                    ? "No budget"
                    : `Now ${money(update.currentLimit, currency)}`}
                </span>
              </span>
              <span className="shrink-0 text-right">
                <span className="block text-sm font-semibold text-ink">
                  {money(update.suggestedLimit, currency)}
                </span>
                <span className="mt-0.5 block text-[10px] font-semibold uppercase tracking-[0.04em] text-green">
                  Suggested
                </span>
              </span>
            </button>
          );
        })}
      </div>

      <div className="flex gap-3">
        <Button variant="secondary" onClick={onDone} className="shrink-0">
          Cancel
        </Button>
        <Button
          className="flex-1"
          enabled={selectedCount > 0}
          onClick={() => {
            applySuggestedBudgets([...selected]);
            onDone();
          }}
        >
          {selectedCount === 0
            ? "Select budgets"
            : selectedCount === 1
              ? "Update 1 budget"
              : `Update ${selectedCount} budgets`}
        </Button>
      </div>
    </div>
  );
}
