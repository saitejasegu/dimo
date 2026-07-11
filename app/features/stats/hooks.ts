import { useMemo } from "react";
import { useAppState } from "@/store/app-store";
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
    const scope = statsScope(statsRange, transactions);
    const { merchants, total } = topMerchants(
      scope,
      merchantsExpanded ? Number.POSITIVE_INFINITY : 3,
    );

    return {
      range: statsRange,
      scope,
      bars: monthBars(statsRange, transactions, selectedMonth),
      categories: statCategories(scope),
      merchants,
      merchantCount: total,
      merchantsExpanded,
    };
  }, [transactions, statsRange, selectedMonth, merchantsExpanded]);
}
