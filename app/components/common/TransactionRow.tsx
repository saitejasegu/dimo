"use client";

import type { Currency, Transaction } from "@/lib/types";
import { spent } from "@/lib/format";
import { cn } from "@/lib/cn";
import { useAppState } from "@/store/app-store";
import { CategoryTint } from "@/components/ui/CategoryTint";
import { Badge } from "@/components/ui/Badge";

interface TransactionRowProps {
  transaction: Transaction;
  currency: Currency;
  onClick: () => void;
  /** "card" = bordered mobile row; "list" = flat hoverable web row. */
  layout?: "card" | "list";
  showDay?: boolean;
  showCategoryPill?: boolean;
  dividerTop?: boolean;
  /** When set, shows a leading checkbox and treats the row as selectable. */
  selected?: boolean;
  selecting?: boolean;
}

export function TransactionRow({
  transaction,
  currency,
  onClick,
  layout = "card",
  showDay = false,
  showCategoryPill = false,
  dividerTop = false,
  selected = false,
  selecting = false,
}: TransactionRowProps) {
  const { categories } = useAppState();
  const emoji =
    transaction.emoji ??
    categories.find((c) => c.id === transaction.categoryId)?.emoji ??
    categories.find((c) => c.name === transaction.category)?.emoji;
  const sub = `${transaction.category} · ${transaction.time}`;

  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={selecting ? selected : undefined}
      className={cn(
        "flex w-full items-center gap-3 text-left transition-colors",
        layout === "card"
          ? "rounded-[14px] !border !border-line !bg-surface !px-3 !py-[11px] hover:!border-green"
          : "-mx-2 rounded-xl px-2 py-3 hover:bg-canvas",
        dividerTop && "border-t border-line-soft",
        selecting && selected && layout === "card" && "!border-green !bg-green-soft/40",
        selecting && selected && layout === "list" && "bg-green-soft/40",
      )}
    >
      {selecting ? (
        <span
          aria-hidden
          className={cn(
            "flex h-5 w-5 shrink-0 items-center justify-center rounded-md border-2 transition-colors",
            selected
              ? "border-green bg-green text-on-green"
              : "border-line bg-surface",
          )}
        >
          {selected ? (
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
              <path
                d="M2.5 6.2l2.4 2.4 4.6-5"
                stroke="currentColor"
                strokeWidth="1.8"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
          ) : null}
        </span>
      ) : (
        <CategoryTint green={transaction.green} emoji={emoji} />
      )}
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm font-medium text-ink">
          {transaction.name}
        </span>
        <span className="block truncate text-xs text-muted">{sub}</span>
      </span>

      {showCategoryPill ? (
        <Badge label={transaction.category} tone="muted" />
      ) : null}

      {showDay ? (
        <span className="w-[110px] shrink-0 text-xs text-faint">
          {transaction.day}
        </span>
      ) : null}

      <span
        className={cn(
          "font-display text-[15px] font-semibold text-ink",
          layout === "list" && "w-[88px] text-right",
        )}
      >
        {spent(transaction.amount, currency)}
      </span>
    </button>
  );
}
