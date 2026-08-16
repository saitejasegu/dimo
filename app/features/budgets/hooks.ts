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
      budgets: categoryBudgets(scoped, limits),
      totals: budgetTotals(scoped, limits),
    };
  }, [transactions, categories]);
}
