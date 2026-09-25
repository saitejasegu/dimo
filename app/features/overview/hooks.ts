import { useMemo } from "react";
import { useAppState } from "@/store/app-store";
import {
  budgetTotals,
  currentMonthTransactions,
  dailyBudgetAllowance,
  topCategories,
} from "@/features/budgets/selectors";
import { recurringAmountInDefault } from "@/features/currency/rates";
import {
  activeRecurring,
  monthlyRecurringTotal,
  upcomingSchedule,
} from "@/features/recurring/selectors";
import { activeCategoryLimits } from "@/features/transactions/selectors";

export function useOverview() {
  const { transactions, recurring, categories, currency, rates } = useAppState("transactions", "recurring", "categories", "currency", "rates");

  return useMemo(() => {
    const limits = activeCategoryLimits(categories);
    const now = new Date();
    // One scan of the full history; the month-scoped figures below reuse it.
    const monthTransactions = currentMonthTransactions(transactions, now);
    // Spent counts every transaction in the month, so the hero total agrees with the
    // list under it and with Stats. Archiving a category stops it earning a budget,
    // it does not erase what it already spent.
    const totals = budgetTotals(monthTransactions, limits);
    const active = activeRecurring(recurring);
    const { upcoming, allUpcoming } = upcomingSchedule(recurring, transactions, now);
    const upcomingTotal = upcoming.reduce(
      (sum, bill) => sum + recurringAmountInDefault(bill, currency, rates),
      0,
    );
    return {
      totals,
      dailyAllowanceAfterUpcoming: dailyBudgetAllowance(totals, now, upcomingTotal),
      recurringTotal: monthlyRecurringTotal(recurring, (r) =>
        recurringAmountInDefault(r, currency, rates),
      ),
      activeCount: active.length,
      recent: transactions,
      upcoming,
      allUpcoming,
      topCategories: topCategories(monthTransactions, 4),
      transactionCount: monthTransactions.length,
    };
  }, [transactions, recurring, categories, currency, rates]);
}
