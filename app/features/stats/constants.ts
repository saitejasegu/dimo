import type { StatsRange } from "@/lib/types";

export const STATS_RANGES: StatsRange[] = ["M", "3M", "6M", "1Y", "2Y"];
export const RANGE_LABEL: Record<StatsRange, string> = {
  M: "1 month",
  "3M": "3 months",
  "6M": "6 months",
  "1Y": "1 year",
  "2Y": "2 years",
};
export const RANGE_MONTHS: Record<StatsRange, number> = {
  M: 1,
  "3M": 3,
  "6M": 6,
  "1Y": 12,
  "2Y": 24,
};
