"use client";

import { money } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { useStats } from "@/features/stats/hooks";
import { Card, HeroCard } from "@/components/ui/Card";
import { StatsRangeDropdown } from "@/components/common/StatsRangeDropdown";
import { CategoryBar } from "@/components/common/CategoryBar";
import { MonthBars } from "@/components/common/MonthBars";
import { MerchantRow } from "@/components/common/MerchantRow";
import { MobileScreen } from "@/components/mobile/MobileScreen";

export function StatsScreen() {
  const { currency } = useAppState();
  const actions = useAppActions();
  const {
    range,
    scope,
    bars,
    categories,
    categoryCount,
    categoriesExpanded,
    merchants,
    merchantCount,
    merchantsExpanded,
  } = useStats();

  return (
    <MobileScreen
      header={
        <>
          <div className="flex items-center justify-between gap-4">
            <h1 className="font-display text-2xl font-semibold text-ink">
              Stats
            </h1>
            <StatsRangeDropdown
              value={range}
              onChange={actions.setStatsRange}
              onChangeDefaults={actions.manageStatsDefaults}
            />
          </div>
          <HeroCard className="mt-4 p-5">
            <div className="mb-2 text-[13px] text-side-muted">
              {scope.spentLabel}
            </div>
            <div className="mb-1.5 font-display text-3xl font-semibold">
              {money(scope.scopeTotal, currency)}
            </div>
            <div className="text-xs text-side-sub">{scope.averageLabel}</div>
          </HeroCard>
        </>
      }
    >
      {bars.visible ? (
        <Card className="mb-4 p-4">
          <div className="mb-3 flex items-baseline justify-between">
            <span className="text-xs font-medium uppercase tracking-[0.08em] text-muted">
              {bars.title}
            </span>
            <span className="text-xs text-muted">{bars.caption}</span>
          </div>
          <MonthBars bars={bars.bars} onSelect={actions.setSelectedMonth} size="mobile" />
        </Card>
      ) : null}

      <Card className="mb-4 p-4">
        <div className="mb-3.5 flex items-center justify-between">
          <span className="text-xs font-medium uppercase tracking-[0.08em] text-muted">
            By category
          </span>
          {categoryCount > 5 ? (
            <button
              type="button"
              onClick={actions.toggleCategories}
              className="text-xs font-medium text-green"
            >
              {categoriesExpanded ? "Show top 5" : `See all (${categoryCount})`}
            </button>
          ) : null}
        </div>
        <div className="flex flex-col gap-3">
          {categories.map((c) => (
            <CategoryBar
              key={c.category}
              label={c.category}
              caption={c.caption}
              value={c.relative}
              tone={c.primary ? "green" : "soft"}
              onClick={() => actions.openCategory(c.category)}
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
            {merchantsExpanded ? "Show top 5" : `Show all (${merchantCount})`}
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
