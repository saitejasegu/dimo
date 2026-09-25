"use client";

import { money } from "@/lib/format";
import { greetingFor } from "@/lib/greeting";
import { useAppActions, useAppState } from "@/store/app-store";
import { useOverview } from "@/features/overview/hooks";
import { Card } from "@/components/ui/Card";
import { BudgetSummary } from "@/components/common/BudgetSummary";
import { UpcomingBillsPanel } from "@/components/common/UpcomingBillsPanel";
import { CategoryBar } from "@/components/common/CategoryBar";
import { WebScreen } from "@/components/web/WebScreen";
import { ActivityScreen } from "@/components/web/screens/ActivityScreen";

export function OverviewScreen() {
  const { profile, currency, rates } = useAppState("profile", "currency", "rates");
  const actions = useAppActions();
  const {
    totals,
    dailyAllowanceAfterUpcoming,
    upcoming,
    allUpcoming,
    topCategories,
    transactionCount,
  } = useOverview();

  const firstName = profile.name.split(" ")[0];
  const showUpcomingSection = allUpcoming.length > 0;

  return (
    <WebScreen>
      <div className="mb-[26px] flex items-end justify-between">
        <div>
          <div className="mb-1 text-sm text-muted">
            {greetingFor()}, {firstName}
          </div>
          <div className="font-display text-[28px] font-semibold text-ink">
            Overview
          </div>
        </div>
        <div className="rounded-full border border-line bg-surface px-4 py-2 text-[13px] text-muted">
          {new Date().toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })}
        </div>
      </div>

      <div className="mb-[22px]">
        <BudgetSummary
          totals={totals}
          afterUpcoming={dailyAllowanceAfterUpcoming}
          currency={currency}
          transactionCount={transactionCount}
        />
      </div>

      <div
        className={`mb-[26px] grid gap-[18px] ${
          showUpcomingSection ? "grid-cols-2" : "grid-cols-1"
        }`}
      >
        {showUpcomingSection && (
          <Card className="h-full p-[22px]">
            <UpcomingBillsPanel
              upcoming={upcoming}
              allUpcoming={allUpcoming}
              currency={currency}
              rates={rates}
              onOpenRecurring={actions.openEditRecurring}
              size="web"
              embedded
            />
          </Card>
        )}

        <Card className="h-full p-[22px]">
          <div className="mb-4 font-display text-[17px] font-semibold text-ink">
            Top categories
          </div>
          <div className="flex flex-col gap-3">
            {topCategories.map((c) => (
              <CategoryBar
                key={c.category}
                label={c.category}
                caption={`${money(c.amount, currency)} · ${c.share}%`}
                value={c.relative}
                tone={c.category === topCategories[0]?.category ? "green" : "soft"}
              />
            ))}
          </div>
        </Card>
      </div>

      <ActivityScreen embedded />
    </WebScreen>
  );
}
