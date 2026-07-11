import type { Currency } from "@/lib/types";
import type { MerchantStat } from "@/features/stats/selectors";
import { money } from "@/lib/format";
import { CategoryTint } from "@/components/ui/CategoryTint";

/** Ranked merchant row with a mini spend bar (stats screen). */
export function MerchantRow({
  merchant,
  currency,
  onClick,
  barWidth = 52,
}: {
  merchant: MerchantStat;
  currency: Currency;
  onClick: () => void;
  barWidth?: number;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="-mx-2 flex items-center gap-3 rounded-[10px] px-2 py-1.5 text-left transition-colors hover:bg-canvas"
    >
      <CategoryTint
        green={merchant.green}
        emoji={merchant.emoji}
        size={34}
        radius={10}
      />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm font-medium text-ink">
          {merchant.name}
        </span>
        <span className="block truncate text-[11px] text-muted">
          {merchant.sub}
        </span>
      </span>
      <span className="flex flex-col items-end gap-1">
        <span className="font-display text-sm font-semibold text-ink">
          {money(merchant.amount, currency)}
        </span>
        <span
          className="block h-1 overflow-hidden rounded-full bg-canvas-deep"
          style={{ width: barWidth }}
        >
          <span
            className="block h-full rounded-full bg-green"
            style={{ width: `${merchant.relative}%` }}
          />
        </span>
      </span>
    </button>
  );
}
