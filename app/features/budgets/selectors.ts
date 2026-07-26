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

/**
 * Epoch bounds of the current local calendar month, so month membership is an integer
 * comparison instead of a `new Date()` plus two getters per transaction.
 */
function currentMonthBounds(now: Date) {
  return {
    start: new Date(now.getFullYear(), now.getMonth(), 1).getTime(),
    end: new Date(now.getFullYear(), now.getMonth() + 1, 1).getTime(),
  };
}

function inCurrentMonth(occurredAt: number | undefined, start: number, end: number) {
  const at = occurredAt ?? 0;
  return at >= start && at < end;
}

export function categoryBudgets(
  transactions: Transaction[],
  limits: CategoryLimits,
): CategoryBudget[] {
  // One pass for every category, rather than a full scan per category.
  const { start, end } = currentMonthBounds(new Date());
  const spentByCategory = new Map<string, number>();
  for (const t of transactions) {
    if (!inCurrentMonth(t.occurredAt, start, end)) continue;
    spentByCategory.set(t.category, (spentByCategory.get(t.category) ?? 0) + t.amount);
  }
  return Object.keys(limits)
    .map((category) => {
      const limit = limits[category];
      const hasLimit = typeof limit === "number" && limit > 0;
      const spent = spentByCategory.get(category) ?? 0;
      const pct = hasLimit ? percent(spent, limit as number) : 0;
      return {
        category,
        spent,
        limit: limit ?? null,
        hasLimit,
        pct,
        over: pct >= 90,
      };
    })
    .sort((a, b) => b.spent - a.spent);
}

export function budgetTotals(
  transactions: Transaction[],
  limits: CategoryLimits,
): BudgetTotals {
  const { start, end } = currentMonthBounds(new Date());
  const current = transactions.filter((t) => inCurrentMonth(t.occurredAt, start, end));
  const totalSpent = current.reduce((sum, t) => sum + t.amount, 0);
  const totalLimit = Object.values(limits).reduce<number>(
    (sum, limit) => sum + (limit ?? 0),
    0,
  );
  const pct = percent(totalSpent, totalLimit);
  return {
    totalSpent,
    totalLimit,
    pct,
    left: totalLimit - totalSpent,
    over: totalLimit > 0 && totalSpent / totalLimit >= 0.9,
  };
}

export interface CategoryLookbackSpend {
  total: number;
  monthlyAverage: number;
  monthCount: number;
}

/** Rolling calendar-month spend for a category — useful when setting a monthly budget. */
export function categoryLookbackSpend(
  transactions: Transaction[],
  categoryId: string,
  monthCount = 6,
  now = new Date(),
): CategoryLookbackSpend {
  const start = new Date(now.getFullYear(), now.getMonth() - (monthCount - 1), 1).getTime();
  const total = transactions
    .filter((t) => t.categoryId === categoryId && (t.occurredAt ?? 0) >= start && (t.occurredAt ?? 0) <= now.getTime())
    .reduce((sum, t) => sum + t.amount, 0);
  return {
    total,
    monthlyAverage: total / monthCount,
    monthCount,
  };
}

export interface SuggestedCategoryBudgetUpdate {
  id: string;
  name: CategoryName;
  suggestedLimit: number;
  currentLimit: number | null;
}

/** Suggested monthly budgets from the last N months of spend. */
export function suggestedCategoryBudgetUpdates(
  transactions: Transaction[],
  categories: Array<{ id: string; name: CategoryName; monthlyBudgetMinor: number | null }>,
  monthCount = 6,
  now = new Date(),
): SuggestedCategoryBudgetUpdate[] {
  return categories.flatMap((category) => {
    const lookback = categoryLookbackSpend(transactions, category.id, monthCount, now);
    if (lookback.total <= 0) return [];
    const suggestedLimit = Math.round(lookback.monthlyAverage);
    const currentLimit =
      category.monthlyBudgetMinor == null ? null : category.monthlyBudgetMinor / 100;
    if (currentLimit === suggestedLimit) return [];
    return [{ id: category.id, name: category.name, suggestedLimit, currentLimit }];
  });
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
  const { start, end } = currentMonthBounds(new Date());
  const byCategory = new Map<CategoryName, number>();
  let total = 0;

  for (const t of transactions) {
    if (!inCurrentMonth(t.occurredAt, start, end)) continue;
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
