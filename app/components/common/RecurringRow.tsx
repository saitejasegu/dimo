"use client";

import { memo } from "react";
import type { Currency, Recurring } from "@/lib/types";
import { money } from "@/lib/format";
import { cn } from "@/lib/cn";
import { recurringSubtitle } from "@/features/recurring/selectors";
import {
  convertMinor,
  toMajorUnits,
  toMinorUnits,
  type RateTable,
} from "@/features/currency/rates";
import { CategoryTint } from "@/components/ui/CategoryTint";
import { Badge } from "@/components/ui/Badge";

function subtitleClass(rec: Recurring): string {
  if (rec.paused) return "text-faint";
  if (rec.urgent) return "font-medium text-warn";
  return "text-muted";
}

/** Mobile: horizontal bordered row with amount + status stacked on the right. */
function RecurringRowImpl({
  recurring,
  currency,
  rates,
  onClick,
}: {
  recurring: Recurring;
  currency: Currency;
  rates: RateTable | null;
  /** Receives the recurring id so callers can pass one stable callback. */
  onClick: (id: string) => void;
}) {
  // Hydration resolves the emoji onto the projection, so no store subscription here.
  const emoji = recurring.emoji;
  const foreign = Boolean(recurring.currency && recurring.currency !== currency);
  const todayMinor = foreign
    ? convertMinor(
        recurring.amountMinor ?? toMinorUnits(recurring.amount, recurring.currency!),
        recurring.currency!,
        currency,
        rates,
      )
    : null;

  return (
    <button
      type="button"
      onClick={() => onClick(recurring.id)}
      className={cn(
        "flex w-full items-center gap-3 rounded-[14px] border border-line bg-surface px-3 py-3 text-left transition-colors hover:border-green",
        recurring.paused && "opacity-65",
      )}
    >
      <CategoryTint green={recurring.green} emoji={emoji} />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm font-medium text-ink">
          {recurring.name}
        </span>
        <span className={cn("block truncate text-xs", subtitleClass(recurring))}>
          {recurringSubtitle(recurring)}
        </span>
      </span>
      <span className="flex flex-col items-end gap-1">
        <span
          className={cn(
            "font-display text-[15px] font-semibold",
            recurring.paused ? "text-faint" : "text-ink",
          )}
        >
          {money(recurring.amount, recurring.currency ?? currency)}
        </span>
        {foreign ? (
          <span className="text-[11px] text-muted">
            {todayMinor != null
              ? `≈ ${money(toMajorUnits(todayMinor, currency), currency)} today`
              : "rate unavailable"}
          </span>
        ) : null}
        <Badge
          label={recurring.paused ? "Paused" : "Active"}
          tone={recurring.paused ? "muted" : "green"}
        />
      </span>
    </button>
  );
}

export const RecurringRow = memo(RecurringRowImpl);
