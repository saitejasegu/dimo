import type { BudgetTotals, DailyBudgetAllowance } from "@/features/budgets/selectors";
import type { Currency } from "@/lib/types";
import { cn } from "@/lib/cn";
import { money } from "@/lib/format";
import { HeroCard } from "@/components/ui/Card";

export function BudgetSummary({
  totals,
  afterUpcoming,
  currency,
  transactionCount,
  className,
}: {
  totals: BudgetTotals;
  afterUpcoming: DailyBudgetAllowance | null;
  currency: Currency;
  transactionCount: number;
  className?: string;
}) {
  const month = new Date().toLocaleDateString(undefined, { month: "short" });
  const days = afterUpcoming
    ? afterUpcoming.daysRemaining === 1 ? "Today" : `${afterUpcoming.daysRemaining} days left`
    : null;
  const transactions = `${transactionCount} ${transactionCount === 1 ? "transaction" : "transactions"}`;
  const hasDaily = afterUpcoming;
  const amount = (value: number) => money(value, currency);
  const metadata = `${month} · ${transactions} · ${totals.pct}% used`;

  return (
    <HeroCard className={cn("overflow-hidden", className)}>
      <div className="px-4 py-3">
        <div className="flex flex-wrap items-baseline justify-between gap-x-2 text-[11px] text-side-muted">
          <span>{hasDaily ? "After upcoming" : "Budget left"}</span>
          <span
            className="text-side-sub"
            title={afterUpcoming ? "Remaining days include today" : undefined}
            aria-label={afterUpcoming ? `${afterUpcoming.daysRemaining} days left, including today` : undefined}
          >{days}</span>
        </div>
        <div className={`break-words font-display text-[30px] font-semibold leading-tight ${!hasDaily && totals.left < 0 ? "text-danger" : "text-green-bright"}`}>
          {amount(hasDaily ? afterUpcoming.amount : totals.left)}
          {hasDaily ? <span className="ml-1 text-xs font-medium text-side-muted">/ day</span> : null}
        </div>
      </div>
      <div className="bg-white/5 px-4 py-2">
        <div className="flex flex-wrap justify-between gap-x-3 text-xs">
          <span className="text-side-muted">Spent <strong className="font-medium text-side-text">{amount(totals.totalSpent)}</strong></span>
          <span className="text-side-muted">Left <strong className={`font-medium ${totals.left < 0 ? "text-danger" : "text-side-text"}`}>{amount(totals.left)}</strong></span>
        </div>
        <div className="mt-1 text-[10px] text-side-sub">{metadata}</div>
      </div>
    </HeroCard>
  );
}
