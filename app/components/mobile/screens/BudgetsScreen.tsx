"use client";

import { money } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { useBudgets } from "@/features/budgets/hooks";
import { Card, HeroCard } from "@/components/ui/Card";
import { ProgressBar } from "@/components/ui/ProgressBar";
import { MobileScreen } from "@/components/mobile/MobileScreen";

export function BudgetsScreen() {
  const { currency, categories } = useAppState();
  const actions = useAppActions();
  const { budgets, totals } = useBudgets();

  return (
    <MobileScreen
      header={
        <>
          <div className="mb-4">
            <h1 className="font-display text-2xl font-semibold text-ink">Budgets</h1>
          </div>
          <HeroCard className="p-5">
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
                <span className="text-sm font-medium text-ink">{b.category}</span>
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
    </MobileScreen>
  );
}
