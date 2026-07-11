"use client";

import { spent } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { useActivity } from "@/features/transactions/hooks";
import { useActivitySelection } from "@/features/transactions/useActivitySelection";
import { ActivitySelectionBar } from "@/components/common/ActivitySelectionBar";
import { Chip } from "@/components/ui/Chip";
import { SearchInput } from "@/components/ui/SearchInput";
import { TransactionRow } from "@/components/common/TransactionRow";
import { MobileScreen } from "@/components/mobile/MobileScreen";

export function ActivityScreen() {
  const { query, currency, categories } = useAppState();
  const actions = useAppActions();
  const { options, filter, groups, filtered } = useActivity();
  const emojiByName = new Map(categories.map((c) => [c.name, c.emoji]));
  const selection = useActivitySelection(filtered.map((tx) => tx.id));

  return (
    <MobileScreen
      header={
        <>
          <div
            className={
              selection.selecting
                ? "mb-3.5 flex flex-col gap-3"
                : "mb-3.5 flex items-center justify-between gap-3"
            }
          >
            <h1 className="font-display text-2xl font-semibold text-ink">
              Transactions
            </h1>
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
              className={selection.selecting ? undefined : "shrink-0"}
            />
          </div>
          <SearchInput
            value={query}
            onChange={actions.setQuery}
            className="mb-3"
          />
          <div className="flex min-w-0 items-center gap-2">
            <Chip
              label="All"
              selected={filter === "All"}
              onClick={() => actions.setFilter("All")}
            />
            <div
              aria-hidden
              className="h-5 w-px shrink-0 bg-hairline"
            />
            <div className="flex min-w-0 flex-1 flex-nowrap gap-2 overflow-x-auto overscroll-x-contain [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
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
        </>
      }
    >
      {groups.length === 0 ? (
        <div className="px-5 py-12 text-center text-sm text-faint">
          No transactions match.
        </div>
      ) : (
        groups.map((group) => (
          <div key={group.label} className="mb-[18px]">
            <div className="mb-2 flex items-baseline justify-between">
              <span className="text-xs font-medium uppercase tracking-[0.08em] text-muted">
                {group.label}
              </span>
              <span className="text-xs text-faint">
                {spent(group.total, currency)}
              </span>
            </div>
            <div className="flex flex-col gap-2">
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
                />
              ))}
            </div>
          </div>
        ))
      )}
    </MobileScreen>
  );
}
