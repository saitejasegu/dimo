import type { CategoryLimits, CategoryName, Transaction } from "@/lib/types";
import { percent } from "@/lib/format";

export interface CategoryBudget {
  category: CategoryName;
  spent: number;
  limit: number | null;
  hasLimit: boolean;
  pct: number;
  /** True once spending reaches 90% of the limit. */
  over: boolean;
}

export interface BudgetTotals {
  totalSpent: number;
  totalLimit: number;
  pct: number;
  left: number;
  over: boolean;
}

function spentByCategory(
  transactions: Transaction[],
  category: CategoryName,
): number {
  return transactions
    .filter((t) => t.category === category)
    .reduce((sum, t) => sum + t.amount, 0);
}

export function categoryBudgets(
  transactions: Transaction[],
  limits: CategoryLimits,
): CategoryBudget[] {
  return Object.keys(limits).map((category) => {
    const limit = limits[category];
    const hasLimit = typeof limit === "number" && limit > 0;
    const spent = spentByCategory(transactions, category);
    const pct = hasLimit ? percent(spent, limit as number) : 0;
    return {
      category,
      spent,
      limit: limit ?? null,
      hasLimit,
      pct,
      over: pct >= 90,
    };
  });
}

export function budgetTotals(
  transactions: Transaction[],
  limits: CategoryLimits,
): BudgetTotals {
  const totalSpent = transactions.reduce((sum, t) => sum + t.amount, 0);
  const totalLimit = Object.values(limits).reduce<number>(
    (sum, limit) => sum + (limit ?? 0),
    0,
  );
  const pct = percent(totalSpent, totalLimit);
  return {
    totalSpent,
    totalLimit,
    pct,
    left: Math.max(0, totalLimit - totalSpent),
    over: totalLimit > 0 && totalSpent / totalLimit >= 0.9,
  };
}

export interface TopCategory {
  category: CategoryName;
  amount: number;
  share: number;
  /** Bar width as a percentage of the largest category. */
  relative: number;
}

/** Categories ranked by spend, used on the overview screen. */
export function topCategories(
  transactions: Transaction[],
  limit: number,
): TopCategory[] {
  const byCategory = new Map<CategoryName, number>();
  let total = 0;

  for (const t of transactions) {
    byCategory.set(t.category, (byCategory.get(t.category) ?? 0) + t.amount);
    total += t.amount;
  }

  const sorted = [...byCategory.entries()].sort((a, b) => b[1] - a[1]);
  const max = sorted.length ? sorted[0][1] : 1;

  return sorted.slice(0, limit).map(([category, amount]) => ({
    category,
    amount,
    share: percent(amount, total),
    relative: Math.max(6, Math.round((amount / max) * 100)),
  }));
}
