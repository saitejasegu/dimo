import { useMemo } from "react";
import { useAppState } from "@/store/app-store";
import {
  filterOptions,
  filterTransactions,
  groupByDay,
  paymentMethodFilterOptions,
  summarize,
} from "@/features/transactions/selectors";

export function useActivity() {
  const { transactions, filter, paymentFilter, query, limits } = useAppState();

  return useMemo(() => {
    const paymentOptions = paymentMethodFilterOptions(transactions);
    const effectivePaymentFilter =
      paymentOptions.length > 1 ? paymentFilter : "All";
    const filtered = filterTransactions(transactions, {
      categories: filter,
      paymentMethod: effectivePaymentFilter,
      query,
    });
    return {
      options: filterOptions(limits),
      filter,
      paymentFilter: effectivePaymentFilter,
      paymentOptions,
      query,
      filtered,
      groups: groupByDay(filtered),
      summary: summarize(filtered),
      totalCount: transactions.length,
      shownCount: filtered.length,
    };
  }, [transactions, filter, paymentFilter, query, limits]);
}
