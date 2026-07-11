"use client";

import { money } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { useOverview } from "@/features/overview/hooks";
import { Avatar } from "@/components/ui/Avatar";
import { Card, HeroCard } from "@/components/ui/Card";
import { TransactionRow } from "@/components/common/TransactionRow";
import { UpcomingRow } from "@/components/common/UpcomingRow";
import { MobileScreen, SectionHeader } from "@/components/mobile/MobileScreen";

export function HomeScreen() {
  const { profile, currency } = useAppState();
  const actions = useAppActions();
  const {
    totals,
    recurringTotal,
    upcoming,
    recent,
    transactionCount,
  } = useOverview();

  const initial = profile.name.charAt(0).toUpperCase();
  const monthSub = `${transactionCount} transactions · ${money(totals.left, currency)} of budget left`;

  return (
    <MobileScreen>
      <div className="mb-[18px] flex items-center justify-between">
        <div>
          <div className="text-[13px] text-muted">Good morning</div>
          <div className="font-display text-[22px] font-semibold text-ink">
            {profile.name}
          </div>
        </div>
        <Avatar initial={initial} onClick={actions.openAccount} />
      </div>

      <HeroCard className="mb-3.5 p-[22px]">
        <div className="mb-2 text-[13px] text-side-muted">Spent in July</div>
        <div className="mb-2 font-display text-[34px] font-semibold">
          {money(totals.totalSpent, currency)}
        </div>
        <div className="text-xs text-side-sub">{monthSub}</div>
      </HeroCard>

      <div className="mb-[22px] grid grid-cols-2 gap-3">
        <Card onClick={() => actions.setView("recurring")} className="p-4">
          <div className="mb-1.5 text-xs text-muted">Recurring / mo</div>
          <div className="font-display text-xl font-semibold text-ink">
            {money(recurringTotal, currency)}
          </div>
        </Card>
        <Card onClick={() => actions.setView("budgets")} className="p-4">
          <div className="mb-1.5 text-xs text-muted">Budget left</div>
          <div className="font-display text-xl font-semibold text-green">
            {money(totals.left, currency)}
          </div>
        </Card>
      </div>

      <SectionHeader
        title="Upcoming this month"
        actionLabel="See all"
        onAction={() => actions.setView("recurring")}
      />
      <div className="mb-[22px] flex flex-col gap-2">
        {upcoming.slice(0, 3).map((rec) => (
          <UpcomingRow
            key={rec.id}
            recurring={rec}
            currency={currency}
            onClick={() => actions.setView("recurring")}
          />
        ))}
      </div>

      <SectionHeader
        title="Recent"
        actionLabel="See all"
        onAction={() => actions.setView("tx")}
      />
      <div className="flex flex-col gap-2">
        {recent.slice(0, 4).map((tx) => (
          <TransactionRow
            key={tx.id}
            transaction={tx}
            currency={currency}
            onClick={() => actions.openDetail(tx.id)}
          />
        ))}
      </div>
    </MobileScreen>
  );
}
