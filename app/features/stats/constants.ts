import type { StatsRange } from "@/lib/types";

export const STATS_RANGES: StatsRange[] = ["M", "3M", "6M", "1Y"];
export const RANGE_LABEL: Record<StatsRange, string> = {
  M: "Month",
  "3M": "3 months",
  "6M": "6 months",
  "1Y": "1 year",
};
export const RANGE_MONTHS: Record<StatsRange, number> = { M: 1, "3M": 3, "6M": 6, "1Y": 12 };
