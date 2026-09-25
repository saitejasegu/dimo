import { useMemo } from "react";
import { useAppState } from "@/store/app-store";
import { recurringAmountInDefault } from "@/features/currency/rates";
import {
  activeRecurring,
  monthlyRecurringTotal,
} from "@/features/recurring/selectors";

export function useRecurring() {
  const { recurring, currency, rates } = useAppState("recurring", "currency", "rates");

  return useMemo(() => {
    const active = activeRecurring(recurring);
    return {
      all: recurring,
      active,
      total: monthlyRecurringTotal(recurring, (r) => recurringAmountInDefault(r, currency, rates)),
      subtitle: active.length ? `${active.length} active · ${active[0].due.toLowerCase()}` : "No active recurring expenses",
    };
  }, [recurring, currency, rates]);
}
