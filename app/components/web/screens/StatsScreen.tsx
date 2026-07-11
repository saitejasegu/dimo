"use client";

import { money } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { useStats } from "@/features/stats/hooks";
import { RANGE_LABEL, STATS_RANGES } from "@/features/stats/constants";
import { Card, HeroCard } from "@/components/ui/Card";
import { SegmentedControl } from "@/components/ui/SegmentedControl";
import { CategoryBar } from "@/components/common/CategoryBar";
import { MonthBars } from "@/components/common/MonthBars";
import { MerchantRow } from "@/components/common/MerchantRow";
import { WebScreen } from "@/components/web/WebScreen";

const RANGE_OPTIONS = STATS_RANGES.map((value) => ({
  value,
  label: RANGE_LABEL[value],
}));

export function StatsScreen() {
  const { currency } = useAppState();
  const actions = useAppActions();
  const { range, scope, bars, categories, merchants, merchantCount, merchantsExpanded } =
    useStats();

  return (
    <WebScreen>
      <div className="mb-[22px] flex items-center justify-between">
        <div className="font-display text-[28px] font-semibold text-ink">
          Stats
        </div>
        <SegmentedControl
          options={RANGE_OPTIONS}
          value={range}
          onChange={actions.setStatsRange}
          fill={false}
        />
      </div>

      <div className="mb-[18px] grid grid-cols-[1fr_1.8fr] items-stretch gap-[18px]">
        <HeroCard className="flex flex-col justify-center p-6">
          <div className="mb-2.5 text-[13px] text-side-muted">
            {scope.spentLabel}
          </div>
          <div className="mb-2 font-display text-[38px] font-semibold">
            {money(scope.scopeTotal, currency)}
          </div>
          <div className="text-xs text-side-sub">{scope.averageLabel}</div>
        </HeroCard>

        {bars.visible ? (
          <Card className="p-[22px]">
            <div className="mb-4 flex items-baseline justify-between">
              <span className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">
                By month
              </span>
              <span className="text-xs text-muted">{bars.caption}</span>
            </div>
            <MonthBars bars={bars.bars} onSelect={actions.setSelectedMonth} size="web" />
          </Card>
        ) : (
          <Card className="flex items-center justify-center p-[22px] text-center text-[13px] text-faint">
            Pick a longer range (3M, 6M, 1Y) to see the month-by-month trend.
          </Card>
        )}
      </div>

      <div className="grid grid-cols-2 items-start gap-[18px]">
        <Card className="p-[22px]">
          <div className="mb-[18px] text-xs font-semibold uppercase tracking-[0.08em] text-muted">
            By category
          </div>
          <div className="flex flex-col gap-[15px]">
            {categories.map((c) => (
              <CategoryBar
                key={c.category}
                label={c.category}
                caption={c.caption}
                value={c.relative}
                tone={c.primary ? "green" : "soft"}
                height={7}
              />
            ))}
          </div>
        </Card>

        <Card className="p-[22px]">
          <div className="mb-3.5 flex items-center justify-between">
            <span className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">
              Top merchants
            </span>
            <button
              type="button"
              onClick={actions.toggleMerchants}
              className="text-xs font-medium text-green"
            >
              {merchantsExpanded ? "Show top 3" : `Show all (${merchantCount})`}
            </button>
          </div>
          <div className="flex flex-col gap-1">
            {merchants.map((m) => (
              <MerchantRow
                key={m.name}
                merchant={m}
                currency={currency}
                onClick={() => actions.openMerchant(m.name)}
                barWidth={64}
              />
            ))}
          </div>
          <p className="mt-3 text-[11px] text-faint">
            Click a merchant to see its transactions.
          </p>
        </Card>
      </div>
    </WebScreen>
  );
}
