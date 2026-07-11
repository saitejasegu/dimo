import type { Currency, Transaction } from "@/lib/types";
import { spent } from "@/lib/format";
import { cn } from "@/lib/cn";
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
}

export function TransactionRow({
  transaction,
  currency,
  onClick,
  layout = "card",
  showDay = false,
  showCategoryPill = false,
  dividerTop = false,
}: TransactionRowProps) {
  const sub = `${transaction.category} · ${transaction.time}`;

  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "flex w-full items-center gap-3 text-left transition-colors",
        layout === "card"
          ? "rounded-[14px] border border-line bg-surface px-3 py-[11px] hover:border-green"
          : "-mx-2 rounded-xl px-2 py-3 hover:bg-canvas",
        dividerTop && "border-t border-line-soft",
      )}
    >
      <CategoryTint green={transaction.green} />
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
