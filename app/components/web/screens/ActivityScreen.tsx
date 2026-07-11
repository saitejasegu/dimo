"use client";

import { useState } from "react";
import { money, spent } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { useActivity } from "@/features/transactions/hooks";
import { PaymentMethodFilter } from "@/components/common/PaymentMethodFilter";
import { Card } from "@/components/ui/Card";
import { SearchInput } from "@/components/ui/SearchInput";
import { TransactionRow } from "@/components/common/TransactionRow";
import { WebScreen } from "@/components/web/WebScreen";
import { Modal } from "@/components/ui/Modal";
import { FilterIcon } from "@/components/ui/icons";
import { CategoryMultiSelect } from "@/components/common/CategoryMultiSelect";
import { Button } from "@/components/ui/Button";

export function ActivityScreen({ embedded = false }: { embedded?: boolean }) {
  const [filtersOpen, setFiltersOpen] = useState(false);
  const { query, currency, categories } = useAppState();
  const actions = useAppActions();
  const {
    options,
    filter,
    paymentFilter,
    paymentOptions,
    groups,
    summary,
    shownCount,
    totalCount,
  } = useActivity();
  const emojiByName = new Map(categories.map((c) => [c.name, c.emoji]));
  const filtersActive = query.trim() !== "" || filter.length > 0 || paymentFilter !== "All";

  const content = (
    <>
      <div className="mb-[22px] flex items-end justify-between gap-4">
        <div>
          <div className="font-display text-[28px] font-semibold text-ink">
            Activity
          </div>
          <div className="mt-1 text-[13px] text-muted">
            {shownCount} of {totalCount} transactions shown
          </div>
        </div>
        <button type="button" aria-label={filtersActive ? "Filter transactions, filters applied" : "Filter transactions"} onClick={() => setFiltersOpen(true)} className={`flex h-9 w-9 items-center justify-center ${filtersActive ? "!text-green" : "!text-muted"}`}><FilterIcon /></button>
      </div>

      <div className="grid grid-cols-[1fr_300px] items-start gap-5">
        <div>
          {groups.length === 0 ? (
            <Card className="px-5 py-16 text-center text-sm text-faint">
              No transactions match your filters.
            </Card>
          ) : (
            groups.map((group) => (
              <Card key={group.label} className="mb-4 px-[22px] py-2">
                <div className="flex items-baseline justify-between pb-1.5 pt-3.5">
                  <span className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">
                    {group.label}
                  </span>
                  <span className="text-xs text-faint">
                    {spent(group.total, currency)}
                  </span>
                </div>
                <div className="flex flex-col">
                  {group.items.map((tx) => (
                    <TransactionRow
                      key={tx.id}
                      transaction={tx}
                      currency={currency}
                      onClick={() => actions.openDetail(tx.id)}
                      layout="list"
                      showCategoryPill
                      dividerTop
                    />
                  ))}
                </div>
              </Card>
            ))
          )}
        </div>

        <Card className="sticky top-0 p-[22px]">
          <div className="mb-4 text-xs font-semibold uppercase tracking-[0.08em] text-muted">
            Summary
          </div>
          <div className="mb-[18px]">
            <div className="mb-1 text-xs text-muted">Filtered total</div>
            <div className="font-display text-[26px] font-semibold text-ink">
              {money(summary.total, currency)}
            </div>
          </div>
          <div className="flex flex-col gap-3 text-[13px]">
            <div className="flex justify-between">
              <span className="text-muted">Transactions</span>
              <span className="font-medium text-ink">{summary.count}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted">Largest</span>
              <span className="font-medium text-ink">
                {summary.largest ? money(summary.largest, currency) : "—"}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted">Top category</span>
              <span className="font-medium text-ink">
                {summary.topCategory ?? "—"}
              </span>
            </div>
          </div>
        </Card>
      </div>
      {filtersOpen ? <Modal title="Filter transactions" onClose={() => setFiltersOpen(false)}>
        <div className="mb-2 text-xs font-semibold uppercase tracking-[0.08em] text-muted">Search</div>
        <SearchInput value={query} onChange={actions.setQuery} className="mb-5" />
        <div className="mb-2 text-xs font-semibold uppercase tracking-[0.08em] text-muted">Categories</div>
        <div className="mb-5"><CategoryMultiSelect options={options.filter((option) => option !== "All")} value={filter} emojiByName={emojiByName} onToggle={actions.setFilter} onClear={() => actions.setFilter("All")} /></div>
        {paymentOptions.length > 1 ? <><div className="mb-2 text-xs font-semibold uppercase tracking-[0.08em] text-muted">Payment methods</div><PaymentMethodFilter inputStyle value={paymentFilter} options={paymentOptions} onChange={actions.setPaymentFilter} className="w-full" /></> : null}
        <div className="mt-5 flex gap-3">
          <Button variant="secondary" fullWidth onClick={() => { actions.setQuery(""); actions.setFilter("All"); actions.setPaymentFilter("All"); setFiltersOpen(false); }}>Clear</Button>
          <Button variant="accent" fullWidth onClick={() => setFiltersOpen(false)}>Done</Button>
        </div>
      </Modal> : null}
    </>
  );
  return embedded ? content : <WebScreen>{content}</WebScreen>;
}
