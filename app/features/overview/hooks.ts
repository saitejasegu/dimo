import { useMemo } from "react";
import { useAppState } from "@/store/app-store";
import {
  budgetTotals,
  dailyBudgetAllowance,
  topCategories,
} from "@/features/budgets/selectors";
import { recurringAmountInDefault } from "@/features/currency/rates";
import {
  activeRecurring,
  allUpcomingBills,
  monthlyRecurringTotal,
  upcomingBills,
} from "@/features/recurring/selectors";
import { activeCategoryLimits } from "@/features/transactions/selectors";

export function useOverview() {
  const { transactions, recurring, categories, currency, rates } = useAppState();

  return useMemo(() => {
    const limits = activeCategoryLimits(categories);
    // Spent counts every transaction in the month, so the hero total agrees with the
    // list under it and with Stats. Archiving a category stops it earning a budget,
    // it does not erase what it already spent.
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
      dailyAllowance: dailyBudgetAllowance(totals, now),
      recurringTotal: monthlyRecurringTotal(recurring, (r) =>
        recurringAmountInDefault(r, currency, rates),
      ),
      activeCount: active.length,
      recent: transactions,
      upcoming: upcomingBills(recurring, transactions),
      allUpcoming: allUpcomingBills(recurring, transactions),
      topCategories: topCategories(transactions, 4),
      transactionCount: monthTransactions.length,
    };
  }, [transactions, recurring, categories, currency, rates]);
}
