import { useMemo } from "react";
import { useAppState } from "@/store/app-store";
import {
  budgetTotals,
  categoryBudgets,
} from "@/features/budgets/selectors";
import {
  activeCategoryLimits,
  transactionsForActiveCategories,
} from "@/features/transactions/selectors";

export function useBudgets() {
  const { transactions, categories } = useAppState();

  return useMemo(() => {
    const limits = activeCategoryLimits(categories);
    const scoped = transactionsForActiveCategories(transactions, categories);
    return {
      // Rows stay scoped: they group by name, so an archived category would
      // otherwise donate its spend to a new active one sharing its name.
      budgets: categoryBudgets(scoped, limits),
      // Totals cover all spend, matching the overview hero.
      totals: budgetTotals(transactions, limits),
    };
  }, [transactions, categories]);
}
