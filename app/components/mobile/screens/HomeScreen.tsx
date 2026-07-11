"use client";

import { useEffect, useState } from "react";
import { money, spent } from "@/lib/format";
import { greetingFor } from "@/lib/greeting";
import { useAppActions, useAppState } from "@/store/app-store";
import { useOverview } from "@/features/overview/hooks";
import { useActivity } from "@/features/transactions/hooks";
import {
  groupByDay,
  HOME_TRANSACTION_PAGE_SIZE,
  paginateTransactionsByDay,
} from "@/features/transactions/selectors";
import { Avatar } from "@/components/ui/Avatar";
import { HeroCard } from "@/components/ui/Card";
import { TransactionRow } from "@/components/common/TransactionRow";
import { PaymentMethodFilter } from "@/components/common/PaymentMethodFilter";
import { SearchInput } from "@/components/ui/SearchInput";
import { Sheet } from "@/components/ui/Sheet";
import { FilterIcon } from "@/components/ui/icons";
import { CategoryMultiSelect } from "@/components/common/CategoryMultiSelect";
import { Button } from "@/components/ui/Button";
import { UpcomingRow } from "@/components/common/UpcomingRow";
import { MobileScreen, MobileTopBar, SectionHeader } from "@/components/mobile/MobileScreen";

export function HomeScreen() {
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [visibleLimit, setVisibleLimit] = useState(HOME_TRANSACTION_PAGE_SIZE);
  const { profile, currency, query, categories } = useAppState();
  const actions = useAppActions();
  const {
    totals,
    upcoming,
    transactionCount,
  } = useOverview();
  const { options, filter, paymentFilter, paymentOptions, filtered } = useActivity();
  const { items: visible, hasMore } = paginateTransactionsByDay(filtered, visibleLimit);
  const groups = groupByDay(visible);
  const emojiByName = new Map(categories.map((category) => [category.name, category.emoji]));
  const filtersActive = query.trim() !== "" || filter.length > 0 || paymentFilter !== "All";

  useEffect(() => {
    setVisibleLimit(HOME_TRANSACTION_PAGE_SIZE);
  }, [query, filter, paymentFilter]);

  const initial = profile.name.charAt(0).toUpperCase();
  const monthSub = `${transactionCount} transactions`;
  const upcomingTotal = upcoming.reduce((total, item) => total + item.amount, 0);

  return (
    <MobileScreen
      header={
        <>
          <MobileTopBar
            subtitle={greetingFor()}
            title={profile.name}
            trailing={
              <Avatar initial={initial} src={profile.photoUrl} onClick={actions.openAccount} />
            }
          />
          <HeroCard className="mt-4 p-[22px]">
            <div className="mb-2 text-[13px] text-side-muted">
              Spent in {new Date().toLocaleDateString(undefined, { month: "long" })}
            </div>
            <div className="mb-2 font-display text-[34px] font-semibold">
              {money(totals.totalSpent, currency)}
            </div>
            <div className="flex items-end justify-between gap-4">
              <div className="text-xs text-side-sub">{monthSub}</div>
              <div className="text-right">
                <div className="text-[11px] text-side-muted">Budget left</div>
                <div className={`font-display text-lg font-semibold ${totals.left < 0 ? "text-danger" : "text-green-bright"}`}>{money(totals.left, currency)}</div>
              </div>
            </div>
          </HeroCard>
        </>
      }
    >
      {upcoming.length > 0 && (
        <>
          <SectionHeader
            title="Upcoming"
            actionLabel={money(upcomingTotal, currency)}
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
        </>
      )}

      <div className="mb-3.5 flex items-center justify-between gap-3">
        <h2 className="font-display text-base font-semibold text-ink">Transactions</h2>
        <button type="button" aria-label={filtersActive ? "Filter transactions, filters applied" : "Filter transactions"} onClick={() => setFiltersOpen(true)} className={`flex h-8 w-8 items-center justify-center ${filtersActive ? "!text-green" : "!text-muted"}`}><FilterIcon /></button>
      </div>
      {groups.length === 0 ? <div className="px-5 py-12 text-center text-sm text-faint">No transactions match.</div> : groups.map((group) => <div key={group.label} className="mb-[18px]">
        <div className="mb-2 flex items-baseline justify-between"><span className="text-xs font-medium uppercase tracking-[0.08em] text-muted">{group.label}</span><span className="text-xs text-faint">{spent(group.total, currency)}</span></div>
        <div className="flex flex-col gap-2">{group.items.map((transaction) => <TransactionRow key={transaction.id} transaction={transaction} currency={currency} onClick={() => actions.openDetail(transaction.id)} />)}</div>
      </div>)}
      {hasMore ? (
        <Button
          variant="secondary"
          fullWidth
          size="sm"
          className="mb-2"
          onClick={() => setVisibleLimit((limit) => limit + HOME_TRANSACTION_PAGE_SIZE)}
        >
          Load more
        </Button>
      ) : null}
      {filtersOpen ? <Sheet title="Filter transactions" onClose={() => setFiltersOpen(false)}>
        <div className="mb-2 text-xs font-semibold uppercase tracking-[0.08em] text-muted">Search</div>
        <SearchInput value={query} onChange={actions.setQuery} className="mb-4" />
        <div className="mb-2 text-xs font-semibold uppercase tracking-[0.08em] text-muted">Categories</div>
        <div className="mb-4"><CategoryMultiSelect options={options.filter((option) => option !== "All")} value={filter} emojiByName={emojiByName} onToggle={actions.setFilter} onClear={() => actions.setFilter("All")} /></div>
        {paymentOptions.length > 1 ? <><div className="mb-2 text-xs font-semibold uppercase tracking-[0.08em] text-muted">Payment methods</div><PaymentMethodFilter inputStyle value={paymentFilter} options={paymentOptions} onChange={actions.setPaymentFilter} className="w-full" /></> : null}
        <div className="mt-5 flex gap-3">
          <Button variant="secondary" fullWidth onClick={() => { actions.setQuery(""); actions.setFilter("All"); actions.setPaymentFilter("All"); setFiltersOpen(false); }}>Clear</Button>
          <Button variant="accent" fullWidth onClick={() => setFiltersOpen(false)}>Done</Button>
        </div>
      </Sheet> : null}
    </MobileScreen>
  );
}
