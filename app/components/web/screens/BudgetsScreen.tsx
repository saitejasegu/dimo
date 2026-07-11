"use client";

import { useMemo, useState } from "react";
import { money } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { useBudgets } from "@/features/budgets/hooks";
import { suggestedCategoryBudgetUpdates } from "@/features/budgets/selectors";
import { ApplySuggestedBudgetsForm } from "@/components/forms/ApplySuggestedBudgetsForm";
import { Card, HeroCard } from "@/components/ui/Card";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { Modal } from "@/components/ui/Modal";
import { ProgressBar } from "@/components/ui/ProgressBar";
import { PlusIcon, SparklesIcon } from "@/components/ui/icons";
import { WebScreen } from "@/components/web/WebScreen";

export function BudgetsScreen() {
  const { currency, categories, transactions } = useAppState();
  const actions = useAppActions();
  const { budgets, totals } = useBudgets();
  const [reviewOpen, setReviewOpen] = useState(false);
  const suggestedUpdates = useMemo(
    () => suggestedCategoryBudgetUpdates(transactions, categories),
    [transactions, categories],
  );

  return (
    <WebScreen>
      <div className="mb-[22px] flex items-center justify-between gap-4">
        <div>
          <div className="font-display text-[28px] font-semibold text-ink">
            Budgets
          </div>
          <div className="mt-1 text-[13px] text-muted">
            Spending tracked against your monthly limits.
          </div>
        </div>
        <div className="flex shrink-0 items-center gap-2.5">
          <button
            type="button"
            aria-label="Update budgets"
            onClick={suggestedUpdates.length > 0 ? () => setReviewOpen(true) : undefined}
            className={
              suggestedUpdates.length > 0
                ? "flex h-10 w-10 items-center justify-center rounded-xl border border-line bg-canvas text-green transition-colors hover:bg-canvas-deep"
                : "pointer-events-none flex h-10 w-10 items-center justify-center rounded-xl border border-line bg-canvas text-faint opacity-50"
            }
          >
            <SparklesIcon size={18} />
          </button>
          <Button
            variant="accent"
            size="sm"
            onClick={() => actions.openOverlay("category")}
            leftIcon={<PlusIcon size={15} />}
          >
            New category
          </Button>
        </div>
      </div>

      <HeroCard className="mb-[22px] p-6">
        <div className="mb-2.5 flex items-baseline justify-between">
          <span className="text-[13px] text-side-muted">Monthly budget</span>
          <span className="text-xs text-side-sub">
            {totals.pct}% used · {money(totals.left, currency)} left · 23 days to go
          </span>
        </div>
        <div className="mb-3.5 font-display text-4xl font-semibold">
          {money(totals.totalSpent, currency)}{" "}
          <span className="text-[17px] font-medium text-side-sub">
            of {money(totals.totalLimit, currency)}
          </span>
        </div>
        <ProgressBar
          value={totals.pct}
          tone={totals.over ? "danger" : "green"}
          height={9}
          onDark
        />
      </HeroCard>

      <div className="grid grid-cols-3 gap-4">
        {budgets.map((b) => {
          const category = categories.find((c) => c.name === b.category);
          return (
            <Card
              key={b.category}
              className="p-5"
              onClick={() => {
                if (category) actions.openEditCategory(category.id);
              }}
            >
              <div className="mb-3.5 flex items-center justify-between">
                <span className="text-[15px] font-semibold text-ink">
                  {category?.emoji ? `${category.emoji} ` : ""}
                  {b.category}
                </span>
                <Badge
                  label={b.hasLimit ? `${b.pct}%` : "No budget"}
                  tone={!b.hasLimit ? "muted" : b.over ? "danger" : "green"}
                />
              </div>
              <ProgressBar
                value={b.hasLimit ? b.pct : 0}
                tone={b.over ? "danger" : "green"}
                height={9}
                className="mb-3"
              />
              <div className="text-[13px] text-muted">
                {b.hasLimit
                  ? `${money(b.spent, currency)} of ${money(b.limit as number, currency)}`
                  : `${money(b.spent, currency)} spent`}
              </div>
            </Card>
          );
        })}
      </div>

      {reviewOpen ? (
        <Modal onClose={() => setReviewOpen(false)} title="Suggested budgets" width={460}>
          <ApplySuggestedBudgetsForm
            updates={suggestedUpdates}
            onDone={() => setReviewOpen(false)}
          />
        </Modal>
      ) : null}
    </WebScreen>
  );
}
