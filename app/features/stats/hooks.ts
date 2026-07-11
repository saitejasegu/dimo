import { useMemo } from "react";
import { useAppState } from "@/store/app-store";
import {
  monthBars,
  statCategories,
  statsScope,
  topMerchants,
} from "@/features/stats/selectors";

export function useStats() {
  const {
    transactions,
    statsRange,
    selectedMonth,
    merchantsExpanded,
    categoriesExpanded,
  } = useAppState();

  return useMemo(() => {
    const scope = statsScope(statsRange, transactions);
    const { merchants, total: merchantCount } = topMerchants(
      scope,
      merchantsExpanded ? Number.POSITIVE_INFINITY : 5,
    );
    const { categories, total: categoryCount } = statCategories(
      scope,
      categoriesExpanded ? Number.POSITIVE_INFINITY : 5,
    );

    return {
      range: statsRange,
      scope,
      bars: monthBars(statsRange, transactions, selectedMonth),
      categories,
      categoryCount,
      categoriesExpanded,
      merchants,
      merchantCount,
      merchantsExpanded,
    };
  }, [transactions, statsRange, selectedMonth, merchantsExpanded, categoriesExpanded]);
}
