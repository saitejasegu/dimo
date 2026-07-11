import { useMemo } from "react";
import { useAppState } from "@/store/app-store";
import {
  filterOptions,
  filterTransactions,
  groupByDay,
  summarize,
} from "@/features/transactions/selectors";

export function useActivity() {
  const { transactions, filter, query, limits } = useAppState();

  return useMemo(() => {
    const filtered = filterTransactions(transactions, {
      category: filter,
      query,
    });
    return {
      options: filterOptions(limits),
      filter,
      query,
      filtered,
      groups: groupByDay(filtered),
      summary: summarize(filtered),
      totalCount: transactions.length,
      shownCount: filtered.length,
    };
  }, [transactions, filter, query, limits]);
}
