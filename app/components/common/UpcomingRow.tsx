import type { Currency, Recurring } from "@/lib/types";
import { money } from "@/lib/format";
import { cn } from "@/lib/cn";
import { CategoryTint } from "@/components/ui/CategoryTint";

/** Compact upcoming-bill row used on the home/overview screens. */
export function UpcomingRow({
  recurring,
  currency,
  onClick,
  size = "mobile",
}: {
  recurring: Recurring;
  currency: Currency;
  onClick: () => void;
  size?: "mobile" | "web";
}) {
  const web = size === "web";
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "flex w-full items-center gap-3 text-left transition-colors",
        !web &&
          "rounded-[14px] !border !border-line !bg-surface !px-3 !py-[11px] hover:!border-green",
      )}
    >
      <CategoryTint
        green={recurring.green}
        size={web ? 36 : 38}
        radius={11}
      />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm font-medium text-ink">
          {recurring.name}
        </span>
        <span
          className={cn(
            "block truncate text-xs",
            recurring.urgent ? "font-medium text-warn" : "text-muted",
          )}
        >
          {recurring.due}
        </span>
      </span>
      <span
        className={cn(
          "font-display font-semibold text-ink",
          web ? "text-sm" : "text-[15px]",
        )}
      >
        {money(recurring.amount, currency)}
      </span>
    </button>
  );
}
