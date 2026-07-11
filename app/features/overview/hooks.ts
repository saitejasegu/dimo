import { useMemo } from "react";
import { useAppState } from "@/store/app-store";
import { budgetTotals, topCategories } from "@/features/budgets/selectors";
import {
  activeRecurring,
  monthlyRecurringTotal,
  upcomingBills,
} from "@/features/recurring/selectors";

export function useOverview() {
  const { transactions, recurring, limits } = useAppState();

  return useMemo(() => {
    const totals = budgetTotals(transactions, limits);
    const active = activeRecurring(recurring);
    return {
      totals,
      recurringTotal: monthlyRecurringTotal(recurring),
      activeCount: active.length,
      recent: transactions,
      upcoming: upcomingBills(recurring, 4),
      topCategories: topCategories(transactions, 4),
      transactionCount: transactions.length,
    };
  }, [transactions, recurring, limits]);
}
