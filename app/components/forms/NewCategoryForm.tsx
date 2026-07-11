"use client";

import { money } from "@/lib/format";
import { cn } from "@/lib/cn";
import { useAppActions, useAppState } from "@/store/app-store";
import { categoryLookbackSpend } from "@/features/budgets/selectors";
import { TextField } from "@/components/ui/TextField";
import { EmojiField } from "@/components/ui/EmojiField";
import { Button } from "@/components/ui/Button";

const PRESETS = [1000, 2500, 5000, 10000];

export function NewCategoryForm({ onCancel }: { onCancel?: () => void }) {
  const { categoryDraft, categories, transactions, currency } = useAppState();
  const actions = useAppActions();

  const editing = Boolean(categoryDraft.id);
  const name = categoryDraft.name.trim();
  const duplicate = categories.some(
    (c) =>
      c.name.toLowerCase() === name.toLowerCase() &&
      c.id !== categoryDraft.id,
  );
  const original = editing
    ? categories.find((c) => c.id === categoryDraft.id)
    : undefined;
  const originalLimit =
    original?.monthlyBudgetMinor == null
      ? ""
      : String(original.monthlyBudgetMinor / 100);
  const dirty =
    !editing ||
    name !== (original?.name ?? "") ||
    categoryDraft.emoji !== (original?.emoji ?? "") ||
    categoryDraft.limit !== originalLimit;
  const valid =
    name.length > 0 &&
    !duplicate &&
    (!editing || dirty);

  const selectedLimit =
    parseInt(categoryDraft.limit.replace(/[^0-9]/g, ""), 10) || 0;

  const lookback = categoryDraft.id
    ? categoryLookbackSpend(transactions, categoryDraft.id)
    : null;
  const suggestedAverage =
    lookback && lookback.total > 0 ? Math.round(lookback.monthlyAverage) : null;

  return (
    <div>
      <div className="mb-4">
        <span className="mb-1.5 block text-xs text-muted">Name</span>
        <div className="flex items-center gap-2.5">
          <EmojiField
            value={categoryDraft.emoji}
            onChange={actions.setCategoryEmoji}
          />
          <input
            type="text"
            value={categoryDraft.name}
            onChange={(e) => actions.setCategoryName(e.target.value)}
            placeholder="e.g. Pets, Travel, Health"
            className="min-w-0 flex-1 rounded-xl border border-line bg-canvas px-3.5 py-[11px] text-base text-ink outline-none placeholder:text-faint"
          />
        </div>
      </div>

      <div className="mb-3">
        <span className="mb-1.5 block text-xs text-muted">
          Monthly budget <span className="text-faint">(optional)</span>
        </span>
        {lookback ? (
          <p className="mb-2 text-[11px] leading-snug text-faint">
            {lookback.total > 0
              ? `${money(lookback.total, currency)} spent over the last ${lookback.monthCount} months`
              : `No spend in the last ${lookback.monthCount} months`}
          </p>
        ) : null}
        <TextField
          value={categoryDraft.limit}
          onChange={actions.setCategoryLimit}
          placeholder="₹ amount"
          inputMode="numeric"
        />
      </div>

      <div className="mb-5 flex flex-wrap gap-2">
        {(suggestedAverage != null
          ? [
              { amount: suggestedAverage, suggested: true as const },
              ...PRESETS.filter((preset) => preset !== suggestedAverage).map((amount) => ({
                amount,
                suggested: false as const,
              })),
            ]
          : PRESETS.map((amount) => ({ amount, suggested: false as const }))
        ).map(({ amount, suggested }) => (
          <button
            type="button"
            key={suggested ? `suggested-${amount}` : amount}
            onClick={() => actions.setCategoryLimit(String(amount))}
            className={cn(
              "inline-flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full px-3.5 py-[7px] text-[13px] transition-colors",
              selectedLimit === amount
                ? "bg-ink font-medium text-canvas"
                : suggested
                  ? "border border-green/30 bg-green-soft font-medium text-green-deep"
                  : "border border-line bg-canvas text-body",
            )}
          >
            <span>{money(amount, currency)}</span>
            {suggested ? (
              <span
                className={cn(
                  "rounded-full px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-[0.04em]",
                  selectedLimit === amount
                    ? "bg-canvas/20 text-canvas"
                    : "bg-green/15 text-green-deep",
                )}
              >
                Suggested
              </span>
            ) : null}
          </button>
        ))}
      </div>

      <div className={cn("flex gap-3")}>
        {onCancel ? (
          <Button variant="secondary" onClick={onCancel} className="shrink-0">
            Cancel
          </Button>
        ) : null}
        <Button onClick={actions.saveCategory} enabled={valid} className="flex-1">
          {editing ? "Save category" : "Create category"}
        </Button>
      </div>
    </div>
  );
}
