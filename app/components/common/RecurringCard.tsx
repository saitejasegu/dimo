"use client";

import type { Currency, Recurring } from "@/lib/types";
import { money } from "@/lib/format";
import { cn } from "@/lib/cn";
import { recurringSubtitle } from "@/features/recurring/selectors";
import { useAppState } from "@/store/app-store";
import { CategoryTint } from "@/components/ui/CategoryTint";
import { Badge } from "@/components/ui/Badge";

function subtitleClass(rec: Recurring): string {
  if (rec.paused) return "text-faint";
  if (rec.urgent) return "font-medium text-warn";
  return "text-muted";
}

/** Web: vertical card with header row and amount/status footer row. */
export function RecurringCard({
  recurring,
  currency,
  onClick,
}: {
  recurring: Recurring;
  currency: Currency;
  onClick: () => void;
}) {
  const { categories } = useAppState();
  const emoji =
    recurring.emoji ??
    categories.find((c) => c.id === recurring.categoryId)?.emoji ??
    categories.find((c) => c.name === recurring.category)?.emoji;

  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "w-full rounded-2xl border border-line bg-surface p-[18px] text-left transition-colors hover:border-green",
        recurring.paused && "opacity-70",
      )}
    >
      <div className="mb-3.5 flex items-center gap-3">
        <CategoryTint green={recurring.green} emoji={emoji} size={38} radius={11} />
        <span className="min-w-0 flex-1">
          <span className="block truncate text-sm font-medium text-ink">
            {recurring.name}
          </span>
          <span className={cn("block truncate text-xs", subtitleClass(recurring))}>
            {recurringSubtitle(recurring)}
          </span>
        </span>
      </div>
      <div className="flex items-center justify-between">
        <span
          className={cn(
            "font-display text-lg font-semibold",
            recurring.paused ? "text-faint" : "text-ink",
          )}
        >
          {money(recurring.amount, currency)}
        </span>
        <Badge
          label={recurring.paused ? "Paused" : "Active"}
          tone={recurring.paused ? "muted" : "green"}
        />
      </div>
    </button>
  );
}
