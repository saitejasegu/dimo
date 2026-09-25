"use client";

import { useMemo, useState } from "react";
import { money } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { useBudgets } from "@/features/budgets/hooks";
import { suggestedCategoryBudgetUpdates } from "@/features/budgets/selectors";
import { ApplySuggestedBudgetsForm } from "@/components/forms/ApplySuggestedBudgetsForm";
import { SetGlobalBudgetForm } from "@/components/forms/SetGlobalBudgetForm";
import { Card, HeroCard } from "@/components/ui/Card";
import { ProgressBar } from "@/components/ui/ProgressBar";
import { Sheet } from "@/components/ui/Sheet";
import { BudgetsIcon, SparklesIcon } from "@/components/ui/icons";
import { MobileScreen, MobileTopBar } from "@/components/mobile/MobileScreen";

export function BudgetsScreen() {
  const { currency, categories, transactions } = useAppState("currency", "categories", "transactions");
  const actions = useAppActions();
  const { budgets, totals } = useBudgets();
  const [reviewOpen, setReviewOpen] = useState(false);
  const [totalOpen, setTotalOpen] = useState(false);
  const suggestedUpdates = useMemo(
    () => suggestedCategoryBudgetUpdates(
      transactions,
      categories.filter((category) => !category.archived),
    ),
    [transactions, categories],
  );
  const archivedCategories = useMemo(
    () => categories.filter((category) => category.archived),
    [categories],
  );

  return (
    <>
      <MobileScreen
        header={
          <>
            <MobileTopBar
              title="Budgets"
              trailing={
                <div className="flex items-center gap-1">
                  <button
                    type="button"
                    aria-label="Set monthly budget"
                    onClick={() => setTotalOpen(true)}
                    className="flex h-9 w-9 items-center justify-center rounded-xl text-green"
                  >
                    <BudgetsIcon size={20} />
                  </button>
                  <button
                    type="button"
                    aria-label="Update budgets"
                    onClick={suggestedUpdates.length > 0 ? () => setReviewOpen(true) : undefined}
                    className={
                      suggestedUpdates.length > 0
                        ? "flex h-9 w-9 items-center justify-center rounded-xl text-green"
                        : "pointer-events-none flex h-9 w-9 items-center justify-center rounded-xl text-faint"
                    }
                  >
                    <SparklesIcon size={20} />
                  </button>
                </div>
              }
            />
            <HeroCard className="mt-4 p-5">
              <div className="mb-2 flex items-baseline justify-between">
                <span className="text-[13px] text-side-muted">Monthly budget</span>
                <span className="text-xs text-side-sub">{totals.pct}% used</span>
              </div>
              <div className="mb-3 font-display text-3xl font-semibold">
                {money(totals.totalSpent, currency)}{" "}
                <span className="text-base font-medium text-side-sub">
                  of {money(totals.totalLimit, currency)}
                </span>
              </div>
              <ProgressBar
                value={totals.pct}
                tone={totals.over ? "danger" : "green"}
                height={8}
                onDark
                className="mb-2"
              />
              <div className="text-xs text-side-sub">
                {money(totals.left, currency)} left · {new Date(new Date().getFullYear(), new Date().getMonth() + 1, 0).getDate() - new Date().getDate()} days to go
              </div>
            </HeroCard>
          </>
        }
      >
        <div className="flex flex-col gap-3">
          {budgets.map((b) => {
            const category = categories.find((c) => c.name === b.category);
            return (
              <Card
                key={b.category}
                className="p-4"
                onClick={() => {
                  if (category) actions.openEditCategory(category.id);
                }}
              >
                <div className="mb-2.5 flex items-baseline justify-between">
                  <span className="text-sm font-medium text-ink">
                    {category?.emoji ? `${category.emoji} ` : ""}
                    {b.category}
                  </span>
                  <span className="text-[13px] text-muted">
                    {b.hasLimit
                      ? `${money(b.spent, currency)} of ${money(b.limit as number, currency)}`
                      : `${money(b.spent, currency)} · no budget`}
                  </span>
                </div>
                <ProgressBar
                  value={b.hasLimit ? b.pct : 0}
                  tone={b.over ? "danger" : "green"}
                  height={8}
                />
              </Card>
            );
          })}
        </div>

        {archivedCategories.length ? (
          <div className="mt-6">
            <div className="mb-3 text-xs font-medium uppercase tracking-[0.08em] text-muted">
              Archived
            </div>
            <div className="divide-y divide-line-soft overflow-hidden rounded-2xl border border-line bg-surface">
              {archivedCategories.map((category) => (
                <button
                  key={category.id}
                  type="button"
                  onClick={() => actions.openEditCategory(category.id)}
                  className="flex w-full items-center justify-between gap-3 px-4 py-3 text-left"
                >
                  <span className="truncate text-sm font-medium text-ink">
                    {category.emoji ? `${category.emoji} ` : ""}
                    {category.name}
                  </span>
                  <span className="shrink-0 rounded-full bg-canvas-deep px-2 py-0.5 text-[10px] font-medium text-muted">
                    Archived
                  </span>
                </button>
              ))}
            </div>
            <p className="mt-3 text-[11px] leading-4 text-muted">
              Archived categories stay attached to past transactions.
            </p>
          </div>
        ) : null}
      </MobileScreen>

      {reviewOpen ? (
        <Sheet onClose={() => setReviewOpen(false)} title="Suggested budgets">
          <ApplySuggestedBudgetsForm
            updates={suggestedUpdates}
            onDone={() => setReviewOpen(false)}
          />
        </Sheet>
      ) : null}

      {totalOpen ? (
        <Sheet onClose={() => setTotalOpen(false)} title="Set monthly budget">
          <SetGlobalBudgetForm onDone={() => setTotalOpen(false)} />
        </Sheet>
      ) : null}
    </>
  );
}
