import { useMemo } from "react";
import { useAppState } from "@/store/app-store";
import {
  budgetTotals,
  categoryBudgets,
} from "@/features/budgets/selectors";

export function useBudgets() {
  const { transactions, limits } = useAppState();

  return useMemo(
    () => ({
      budgets: categoryBudgets(transactions, limits),
      totals: budgetTotals(transactions, limits),
    }),
    [transactions, limits],
  );
}
