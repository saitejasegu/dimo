import { useMemo } from "react";
import { useAppState } from "@/store/app-store";
import {
  hasEarlierData,
  statCategories,
  statsScope,
  topMerchants,
  trendBars,
} from "@/features/stats/selectors";

export function useStats() {
  const {
    transactions,
    statsRange,
    statsPeriodOffset,
    selectedMonth,
    merchantsExpanded,
    categoriesExpanded,
  } = useAppState();

  return useMemo(() => {
    const scope = statsScope(statsRange, transactions, new Date(), statsPeriodOffset);
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
      offset: statsPeriodOffset,
      periodLabel: scope.periodLabel,
      canGoBack: hasEarlierData(transactions, statsRange, statsPeriodOffset),
      // Scoped rows only — the bars never cover a period outside the range, and
      // iOS already derives them from the scope.
      bars: trendBars(statsRange, scope.transactions, selectedMonth, new Date(), statsPeriodOffset),
      categories,
      categoryCount,
      categoriesExpanded,
      merchants,
      merchantCount,
      merchantsExpanded,
    };
  }, [
    transactions,
    statsRange,
    statsPeriodOffset,
    selectedMonth,
    merchantsExpanded,
    categoriesExpanded,
  ]);
}
