import { useMemo } from "react";
import { useAppState } from "@/store/app-store";
import {
  activeRecurring,
  monthlyRecurringTotal,
} from "@/features/recurring/selectors";

export function useRecurring() {
  const { recurring } = useAppState();

  return useMemo(() => {
    const active = activeRecurring(recurring);
    return {
      all: recurring,
      active,
      total: monthlyRecurringTotal(recurring),
      subtitle: active.length ? `${active.length} active · ${active[0].due.toLowerCase()}` : "No active recurring expenses",
    };
  }, [recurring]);
}
