"use client";

import { money } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { useBudgets } from "@/features/budgets/hooks";
import { Card, HeroCard } from "@/components/ui/Card";
import { ProgressBar } from "@/components/ui/ProgressBar";
import { PlusIcon } from "@/components/ui/icons";
import { MobileScreen } from "@/components/mobile/MobileScreen";

export function BudgetsScreen() {
  const { currency } = useAppState();
  const actions = useAppActions();
  const { budgets, totals } = useBudgets();

  return (
    <MobileScreen>
      <div className="mb-4 flex items-center justify-between">
        <h1 className="font-display text-2xl font-semibold text-ink">Budgets</h1>
        <button
          type="button"
          onClick={() => actions.openOverlay("category")}
          aria-label="New category"
          className="flex h-[34px] w-[34px] items-center justify-center rounded-[10px] bg-green text-white"
        >
          <PlusIcon size={16} />
        </button>
      </div>

      <HeroCard className="mb-4 p-5">
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
          {money(totals.left, currency)} left · 23 days to go in July
        </div>
      </HeroCard>

      <div className="flex flex-col gap-3">
        {budgets.map((b) => (
          <Card key={b.category} className="p-4">
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
        ))}
      </div>
    </MobileScreen>
  );
}
