"use client";

import { money } from "@/lib/format";
import { greetingFor } from "@/lib/greeting";
import { useAppActions, useAppState } from "@/store/app-store";
import { useOverview } from "@/features/overview/hooks";
import { Card, HeroCard } from "@/components/ui/Card";
import { UpcomingRow } from "@/components/common/UpcomingRow";
import { CategoryBar } from "@/components/common/CategoryBar";
import { WebScreen } from "@/components/web/WebScreen";
import { ActivityScreen } from "@/components/web/screens/ActivityScreen";

export function OverviewScreen() {
  const { profile, currency } = useAppState();
  const actions = useAppActions();
  const {
    totals,
    upcoming,
    topCategories,
    transactionCount,
  } = useOverview();

  const firstName = profile.name.split(" ")[0];
  const monthSub = `${transactionCount} transactions`;
  const upcomingTotal = upcoming.reduce((total, item) => total + item.amount, 0);

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
        <HeroCard className="p-6">
          <div className="mb-2.5 text-[13px] text-side-muted">
            Spent in {new Date().toLocaleDateString(undefined, { month: "long" })}
          </div>
          <div className="mb-2 font-display text-[40px] font-semibold">
            {money(totals.totalSpent, currency)}
          </div>
          <div className="flex items-end justify-between gap-6">
            <div className="text-xs text-side-sub">{monthSub}</div>
            <div className="text-right">
              <div className="text-xs text-side-muted">Budget left</div>
              <div className={`font-display text-2xl font-semibold ${totals.left < 0 ? "text-danger" : "text-green-bright"}`}>{money(totals.left, currency)}</div>
              <div className="text-[11px] text-side-sub">{totals.pct}% used</div>
            </div>
          </div>
        </HeroCard>
      </div>

      <div
        className={`mb-[26px] grid gap-[18px] ${
          upcoming.length > 0 ? "grid-cols-2" : "grid-cols-1"
        }`}
      >
        {upcoming.length > 0 && (
          <Card className="h-full p-[22px]">
            <div className="mb-3.5 flex items-baseline justify-between">
              <span className="font-display text-[17px] font-semibold text-ink">
                Upcoming
              </span>
              <span className="text-[13px] font-medium text-muted">{money(upcomingTotal, currency)}</span>
            </div>
            <div className="flex flex-col gap-3.5">
              {upcoming.map((rec) => (
                <UpcomingRow
                  key={rec.id}
                  recurring={rec}
                  currency={currency}
                  onClick={() => actions.setView("recurring")}
                  size="web"
                />
              ))}
            </div>
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
