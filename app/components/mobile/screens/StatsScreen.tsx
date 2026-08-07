"use client";

import { useState } from "react";
import { money } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { useStats } from "@/features/stats/hooks";
import { Card, HeroCard } from "@/components/ui/Card";
import { StatsRangeDropdown } from "@/components/common/StatsRangeDropdown";
import { StatsPeriodNav } from "@/components/common/StatsPeriodNav";
import {
  StatsTransactionsList,
  type StatsSelection,
} from "@/components/common/StatsTransactionsList";
import { Sheet } from "@/components/ui/Sheet";
import { CategoryBar } from "@/components/common/CategoryBar";
import { MonthBars } from "@/components/common/MonthBars";
import { MerchantRow } from "@/components/common/MerchantRow";
import { MobileScreen, MobileTopBar } from "@/components/mobile/MobileScreen";

export function StatsScreen() {
  const { currency } = useAppState();
  const actions = useAppActions();
  const [selection, setSelection] = useState<StatsSelection | null>(null);
  const {
    range,
    scope,
    offset,
    periodLabel,
    canGoBack,
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
          <MobileTopBar
            title="Stats"
            trailing={
              <StatsRangeDropdown
                value={range}
                onChange={actions.setStatsRange}
                onChangeDefaults={actions.manageStatsDefaults}
              />
            }
          />
          <StatsPeriodNav
            offset={offset}
            label={periodLabel}
            canGoBack={canGoBack}
            onChange={actions.setStatsPeriodOffset}
            className="mt-3"
          />
          <HeroCard className="mt-3 p-5">
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
              onClick={() => setSelection({ kind: "category", name: c.category })}
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
              onClick={() => setSelection({ kind: "merchant", name: m.name })}
            />
          ))}
        </div>
        <p className="mt-2.5 text-[11px] text-faint">
          Tap a merchant to see its transactions.
        </p>
      </Card>

      {selection ? (
        <Sheet onClose={() => setSelection(null)} title={selection.name}>
          <StatsTransactionsList
            selection={selection}
            transactions={scope.transactions}
            currency={currency}
            periodLabel={periodLabel}
            onOpenTransaction={(id) => {
              setSelection(null);
              actions.openDetail(id);
            }}
          />
        </Sheet>
      ) : null}
    </MobileScreen>
  );
}
