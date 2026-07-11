import type { Currency, Recurring } from "@/lib/types";
import { money } from "@/lib/format";
import { cn } from "@/lib/cn";
import { recurringSubtitle } from "@/features/recurring/selectors";
import { CategoryTint } from "@/components/ui/CategoryTint";
import { Badge } from "@/components/ui/Badge";

function subtitleClass(rec: Recurring): string {
  if (rec.paused) return "text-faint";
  if (rec.urgent) return "font-medium text-warn";
  return "text-muted";
}

/** Mobile: horizontal bordered row with amount + status stacked on the right. */
export function RecurringRow({
  recurring,
  currency,
  onClick,
}: {
  recurring: Recurring;
  currency: Currency;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "flex w-full items-center gap-3 rounded-[14px] border border-line bg-surface px-3 py-3 text-left transition-colors hover:border-green",
        recurring.paused && "opacity-65",
      )}
    >
      <CategoryTint green={recurring.green} />
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
          {money(recurring.amount, currency)}
        </span>
        <Badge
          label={recurring.paused ? "Paused" : "Active"}
          tone={recurring.paused ? "muted" : "green"}
        />
      </span>
    </button>
  );
}
