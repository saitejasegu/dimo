"use client";

import type { Currency, Recurring } from "@/lib/types";
import { money } from "@/lib/format";
import { cn } from "@/lib/cn";
import { useAppState } from "@/store/app-store";
import { convertMinor, toMajorUnits, toMinorUnits } from "@/features/currency/rates";
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
  const { categories, rates } = useAppState();
  const emoji =
    recurring.emoji ??
    categories.find((c) => c.id === recurring.categoryId)?.emoji ??
    categories.find((c) => c.name === recurring.category)?.emoji;
  const web = size === "web";
  // Foreign bills show their own-currency amount plus today's default-currency value.
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
      onClick={onClick}
      className={cn(
        "flex w-full items-center gap-3 text-left transition-colors",
        !web &&
          "rounded-[14px] !border !border-line !bg-surface !px-3 !py-[11px] hover:!border-green",
        recurring.paused &&
          (web
            ? "rounded-xl border border-dashed border-hairline bg-canvas-deep/70 px-2.5 py-2"
            : "!border-dashed !border-hairline !bg-canvas-deep/70 hover:!border-hairline"),
      )}
    >
      <CategoryTint
        green={recurring.green}
        emoji={emoji}
        size={web ? 36 : 38}
        radius={11}
        className={cn(recurring.paused && "opacity-60 grayscale")}
      />
      <span className="min-w-0 flex-1">
        <span
          className={cn(
            "block truncate text-sm font-medium",
            recurring.paused ? "text-muted" : "text-ink",
          )}
        >
          {recurring.name}
        </span>
        {recurring.paused ? (
          <span className="mt-1 inline-flex items-center rounded-full border border-hairline bg-surface px-2 py-0.5 text-[10px] font-medium leading-none text-muted">
            Paused
          </span>
        ) : (
          <span
            className={cn(
              "block truncate text-xs",
              recurring.urgent ? "font-medium text-warn" : "text-muted",
            )}
          >
            {recurring.due}
          </span>
        )}
      </span>
      <span className="flex shrink-0 flex-col items-end">
        <span
          className={cn(
            "font-display font-semibold",
            recurring.paused ? "text-muted" : "text-ink",
            web ? "text-sm" : "text-[15px]",
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
      </span>
    </button>
  );
}
