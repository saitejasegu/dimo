"use client";

import { spent } from "@/lib/format";
import { useAppActions, useAppState } from "@/store/app-store";
import { useActivity } from "@/features/transactions/hooks";
import { Chip } from "@/components/ui/Chip";
import { SearchInput } from "@/components/ui/SearchInput";
import { TransactionRow } from "@/components/common/TransactionRow";
import { MobileScreen } from "@/components/mobile/MobileScreen";

export function ActivityScreen() {
  const { query, currency, categories } = useAppState();
  const actions = useAppActions();
  const { options, filter, groups } = useActivity();
  const emojiByName = new Map(categories.map((c) => [c.name, c.emoji]));

  return (
    <MobileScreen
      header={
        <>
          <h1 className="mb-3.5 font-display text-2xl font-semibold text-ink">
            Transactions
          </h1>
          <SearchInput
            value={query}
            onChange={actions.setQuery}
            className="mb-3"
          />
          <div className="flex gap-2 overflow-x-auto overscroll-x-contain pb-0.5">
            {options.map((option) => {
              const emoji = option === "All" ? null : emojiByName.get(option);
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
                  onClick={() => actions.openDetail(tx.id)}
                />
              ))}
            </div>
          </div>
        ))
      )}
    </MobileScreen>
  );
}
