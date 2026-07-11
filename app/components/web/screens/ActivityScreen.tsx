"use client";

import { money, spent } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { useActivity } from "@/features/transactions/hooks";
import { useActivitySelection } from "@/features/transactions/useActivitySelection";
import { ActivitySelectionBar } from "@/components/common/ActivitySelectionBar";
import { Card } from "@/components/ui/Card";
import { Chip } from "@/components/ui/Chip";
import { SearchInput } from "@/components/ui/SearchInput";
import { TransactionRow } from "@/components/common/TransactionRow";
import { WebScreen } from "@/components/web/WebScreen";

export function ActivityScreen() {
  const { query, currency, categories } = useAppState();
  const actions = useAppActions();
  const { options, filter, groups, summary, shownCount, totalCount, filtered } =
    useActivity();
  const emojiByName = new Map(categories.map((c) => [c.name, c.emoji]));
  const selection = useActivitySelection(filtered.map((tx) => tx.id));

  return (
    <WebScreen>
      <div className="mb-[22px] flex items-end justify-between gap-4">
        <div>
          <div className="font-display text-[28px] font-semibold text-ink">
            Activity
          </div>
          <div className="mt-1 text-[13px] text-muted">
            {shownCount} of {totalCount} transactions shown
          </div>
        </div>
        <div className="flex items-center gap-3">
          <ActivitySelectionBar
            selecting={selection.selecting}
            selectedCount={selection.selectedCount}
            allSelected={selection.allSelected}
            visibleCount={filtered.length}
            selectedIds={selection.selectedIds}
            onEnter={selection.enter}
            onExit={selection.exit}
            onSelectAll={selection.selectAll}
            onDeselectAll={selection.deselectAll}
          />
          <SearchInput value={query} onChange={actions.setQuery} className="w-80 py-2.5" />
        </div>
      </div>

      <div className="mb-[22px] flex min-w-0 items-center gap-2.5">
        <Chip
          label="All"
          selected={filter === "All"}
          onClick={() => actions.setFilter("All")}
        />
        <div
          aria-hidden
          className="h-5 w-px shrink-0 bg-hairline"
        />
        <div className="flex min-w-0 flex-1 flex-nowrap gap-2.5 overflow-x-auto overscroll-x-contain [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
          {options
            .filter((option) => option !== "All")
            .map((option) => {
              const emoji = emojiByName.get(option);
              return (
                <Chip
                  key={option}
                  label={emoji ? `${emoji} ${option}` : option}
                  selected={filter === option}
                  onClick={() => actions.setFilter(option)}
                />
              );
            })}
        </div>
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
                      selecting={selection.selecting}
                      selected={selection.selected.has(tx.id)}
                      onClick={() =>
                        selection.selecting
                          ? selection.toggle(tx.id)
                          : actions.openDetail(tx.id)
                      }
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
    </WebScreen>
  );
}
