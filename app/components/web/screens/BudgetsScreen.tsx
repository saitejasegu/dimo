"use client";

import { money } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { useBudgets } from "@/features/budgets/hooks";
import { Card, HeroCard } from "@/components/ui/Card";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { ProgressBar } from "@/components/ui/ProgressBar";
import { PlusIcon } from "@/components/ui/icons";
import { WebScreen } from "@/components/web/WebScreen";

export function BudgetsScreen() {
  const { currency } = useAppState();
  const actions = useAppActions();
  const { budgets, totals } = useBudgets();

  return (
    <WebScreen>
      <div className="mb-[22px] flex items-center justify-between">
        <div>
          <div className="font-display text-[28px] font-semibold text-ink">
            Budgets
          </div>
          <div className="mt-1 text-[13px] text-muted">
            Spending tracked against your monthly limits.
          </div>
        </div>
        <Button
          variant="accent"
          size="sm"
          onClick={() => actions.openOverlay("category")}
          leftIcon={<PlusIcon size={15} />}
        >
          New category
        </Button>
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
        {budgets.map((b) => (
          <Card key={b.category} className="p-5">
            <div className="mb-3.5 flex items-center justify-between">
              <span className="text-[15px] font-semibold text-ink">
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
        ))}
      </div>
    </WebScreen>
  );
}
