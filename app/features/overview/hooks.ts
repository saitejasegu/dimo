import { useMemo } from "react";
import { useAppState } from "@/store/app-store";
import { budgetTotals, topCategories } from "@/features/budgets/selectors";
import { recurringAmountInDefault } from "@/features/currency/rates";
import {
  activeRecurring,
  allUpcomingBills,
  monthlyRecurringTotal,
  upcomingBills,
} from "@/features/recurring/selectors";

export function useOverview() {
  const { transactions, recurring, limits, currency, rates } = useAppState();

  return useMemo(() => {
    const totals = budgetTotals(transactions, limits);
    const active = activeRecurring(recurring);
    const now = new Date();
    const monthTransactions = transactions.filter((t) => {
      const date = new Date(t.occurredAt ?? 0);
      return (
        date.getFullYear() === now.getFullYear() &&
        date.getMonth() === now.getMonth()
      );
    });
    return {
      totals,
      recurringTotal: monthlyRecurringTotal(recurring, (r) =>
        recurringAmountInDefault(r, currency, rates),
      ),
      activeCount: active.length,
      recent: transactions,
      upcoming: upcomingBills(recurring),
      allUpcoming: allUpcomingBills(recurring),
      topCategories: topCategories(transactions, 4),
      transactionCount: monthTransactions.length,
    };
  }, [transactions, recurring, limits, currency, rates]);
}
