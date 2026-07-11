import { useMemo } from "react";
import { useAppState } from "@/store/app-store";
import { totalSpent } from "@/features/transactions/selectors";
import {
  monthBars,
  statCategories,
  statsScope,
  topMerchants,
} from "@/features/stats/selectors";

export function useStats() {
  const { transactions, statsRange, selectedMonth, merchantsExpanded } =
    useAppState();

  return useMemo(() => {
    const currentMonthSpent = totalSpent(transactions);
    const scope = statsScope(statsRange, currentMonthSpent);
    const { merchants, total } = topMerchants(
      transactions,
      statsRange,
      scope,
      merchantsExpanded ? Number.POSITIVE_INFINITY : 3,
    );

    return {
      range: statsRange,
      scope,
      bars: monthBars(statsRange, currentMonthSpent, selectedMonth),
      categories: statCategories(transactions, statsRange, scope),
      merchants,
      merchantCount: total,
      merchantsExpanded,
    };
  }, [transactions, statsRange, selectedMonth, merchantsExpanded]);
}
