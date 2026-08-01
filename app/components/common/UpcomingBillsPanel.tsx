"use client";

import { useState } from "react";
import type { Currency, Recurring } from "@/lib/types";
import { money } from "@/lib/format";
import {
  recurringAmountInDefault,
  type RateTable,
} from "@/features/currency/rates";
import { UpcomingRow } from "@/components/common/UpcomingRow";

export function UpcomingBillsPanel({
  upcoming,
  allUpcoming,
  currency,
  rates,
  onOpenRecurring,
  size = "mobile",
}: {
  upcoming: Recurring[];
  allUpcoming: Recurring[];
  currency: Currency;
  rates: RateTable | null;
  onOpenRecurring: (id: string) => void;
  size?: "mobile" | "web";
}) {
  const [showAll, setShowAll] = useState(false);
  const visibleUpcoming = showAll ? allUpcoming : upcoming;
  const canShowAll = allUpcoming.length > upcoming.length;
  const total = visibleUpcoming.reduce(
    (sum, item) =>
      sum +
      (item.paused
        ? 0
        : recurringAmountInDefault(item, currency, rates)),
    0,
  );

  return (
    <>
      <div className="mb-4">
        <h2 className="text-center font-display text-lg font-semibold text-ink">
          {showAll ? "Upcoming" : "Upcoming this month"}
        </h2>
        <div className="mt-1.5 flex items-baseline justify-between gap-3">
          <span className="text-[13px] font-medium text-muted">
            {money(total, currency)}
          </span>
          {canShowAll || showAll ? (
            <button
              type="button"
              onClick={() => setShowAll((value) => !value)}
              className="text-xs font-medium text-green"
            >
              {showAll ? "This month" : `Show all (${allUpcoming.length})`}
            </button>
          ) : null}
        </div>
      </div>

      <div className="flex max-h-[min(65vh,36rem)] flex-col gap-2 overflow-y-auto overscroll-contain pb-1 pr-1">
        {visibleUpcoming.length === 0 ? (
          <div className="rounded-[14px] border border-line bg-surface px-3 py-[18px] text-center text-sm text-faint">
            None
          </div>
        ) : (
          visibleUpcoming.map((recurring) => (
            <UpcomingRow
              key={recurring.id}
              recurring={recurring}
              currency={currency}
              rates={rates}
              onClick={onOpenRecurring}
              size={size}
            />
          ))
        )}
      </div>
    </>
  );
}
