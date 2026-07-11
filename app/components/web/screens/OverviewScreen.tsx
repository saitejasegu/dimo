"use client";

import { money } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { useOverview } from "@/features/overview/hooks";
import { Card, HeroCard } from "@/components/ui/Card";
import { TransactionRow } from "@/components/common/TransactionRow";
import { UpcomingRow } from "@/components/common/UpcomingRow";
import { CategoryBar } from "@/components/common/CategoryBar";
import { WebScreen } from "@/components/web/WebScreen";

export function OverviewScreen() {
  const { profile, currency } = useAppState();
  const actions = useAppActions();
  const {
    totals,
    recurringTotal,
    activeCount,
    recent,
    upcoming,
    topCategories,
    transactionCount,
  } = useOverview();

  const firstName = profile.name.split(" ")[0];
  const monthSub = `${transactionCount} transactions · ${money(totals.left, currency)} of budget left`;

  return (
    <WebScreen>
      <div className="mb-[26px] flex items-end justify-between">
        <div>
          <div className="mb-1 text-sm text-muted">
            Good morning, {firstName}
          </div>
          <div className="font-display text-[28px] font-semibold text-ink">
            Overview
          </div>
        </div>
        <div className="rounded-full border border-line bg-surface px-4 py-2 text-[13px] text-muted">
          {new Date().toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })}
        </div>
      </div>

      <div className="mb-[22px] grid grid-cols-[1.5fr_1fr_1fr] gap-[18px]">
        <HeroCard className="p-6">
          <div className="mb-2.5 text-[13px] text-side-muted">
            Spent in {new Date().toLocaleDateString(undefined, { month: "long" })}
          </div>
          <div className="mb-2 font-display text-[40px] font-semibold">
            {money(totals.totalSpent, currency)}
          </div>
          <div className="text-xs text-side-sub">{monthSub}</div>
        </HeroCard>

        <Card onClick={() => actions.setView("recurring")} className="h-full p-[22px]">
          <div className="flex h-full flex-col justify-between">
            <div className="mb-3.5 text-[13px] text-muted">Recurring / mo</div>
            <div>
              <div className="font-display text-[28px] font-semibold text-ink">
                {money(recurringTotal, currency)}
              </div>
              <div className="mt-1 text-xs text-faint">
                {activeCount} active bills
              </div>
            </div>
          </div>
        </Card>

        <Card onClick={() => actions.setView("budgets")} className="h-full p-[22px]">
          <div className="flex h-full flex-col justify-between">
            <div className="mb-3.5 text-[13px] text-muted">Budget left</div>
            <div>
              <div className="font-display text-[28px] font-semibold text-green">
                {money(totals.left, currency)}
              </div>
              <div className="mt-1 text-xs text-faint">{totals.pct}% used</div>
            </div>
          </div>
        </Card>
      </div>

      <div className="grid grid-cols-[1.6fr_1fr] items-start gap-[18px]">
        <Card className="p-[22px]">
          <div className="mb-4 flex items-baseline justify-between">
            <span className="font-display text-[17px] font-semibold text-ink">
              Recent transactions
            </span>
            <button
              type="button"
              onClick={() => actions.setView("tx")}
              className="text-[13px] font-medium text-green"
            >
              View all
            </button>
          </div>
          <div className="flex flex-col">
            {recent.slice(0, 6).map((tx) => (
              <TransactionRow
                key={tx.id}
                transaction={tx}
                currency={currency}
                onClick={() => actions.openDetail(tx.id)}
                layout="list"
                showDay
              />
            ))}
          </div>
        </Card>

        <div className="flex flex-col gap-[18px]">
          {upcoming.length > 0 && (
            <Card className="p-[22px]">
              <div className="mb-3.5 flex items-baseline justify-between">
                <span className="font-display text-[17px] font-semibold text-ink">
                  Upcoming
                </span>
                <button
                  type="button"
                  onClick={() => actions.setView("recurring")}
                  className="text-[13px] font-medium !text-green"
                >
                  See all
                </button>
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

          <Card className="p-[22px]">
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
      </div>
    </WebScreen>
  );
}
