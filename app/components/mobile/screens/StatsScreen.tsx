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
import { MobileScreen } from "@/components/mobile/MobileScreen";

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
    <MobileScreen
      header={
        <>
          <h1 className="mb-3.5 font-display text-2xl font-semibold text-ink">
            Stats
          </h1>
          <SegmentedControl
            options={RANGE_OPTIONS}
            value={range}
            onChange={actions.setStatsRange}
          />
        </>
      }
    >
      <HeroCard className="mb-4 p-5">
        <div className="mb-2 text-[13px] text-side-muted">{scope.spentLabel}</div>
        <div className="mb-1.5 font-display text-3xl font-semibold">
          {money(scope.scopeTotal, currency)}
        </div>
        <div className="text-xs text-side-sub">{scope.averageLabel}</div>
      </HeroCard>

      {bars.visible ? (
        <Card className="mb-4 p-4">
          <div className="mb-3 flex items-baseline justify-between">
            <span className="text-xs font-medium uppercase tracking-[0.08em] text-muted">
              By month
            </span>
            <span className="text-xs text-muted">{bars.caption}</span>
          </div>
          <MonthBars bars={bars.bars} onSelect={actions.setSelectedMonth} size="mobile" />
        </Card>
      ) : null}

      <Card className="mb-4 p-4">
        <div className="mb-3.5 text-xs font-medium uppercase tracking-[0.08em] text-muted">
          By category
        </div>
        <div className="flex flex-col gap-3">
          {categories.map((c) => (
            <CategoryBar
              key={c.category}
              label={c.category}
              caption={c.caption}
              value={c.relative}
              tone={c.primary ? "green" : "soft"}
            />
          ))}
        </div>
      </Card>

      <Card className="p-4">
        <div className="mb-3 flex items-center justify-between">
          <span className="text-xs font-medium uppercase tracking-[0.08em] text-muted">
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
        <div className="flex flex-col gap-1.5">
          {merchants.map((m) => (
            <MerchantRow
              key={m.name}
              merchant={m}
              currency={currency}
              onClick={() => actions.openMerchant(m.name)}
            />
          ))}
        </div>
        <p className="mt-2.5 text-[11px] text-faint">
          Tap a merchant to see its transactions.
        </p>
      </Card>
    </MobileScreen>
  );
}
