import type { StatsRange } from "@/lib/types";

export const STATS_RANGES: StatsRange[] = ["1W", "M", "3M", "6M", "1Y", "2Y"];

export const RANGE_LABEL: Record<StatsRange, string> = {
  "1W": "1 week",
  M: "1 month",
  "3M": "3 months",
  "6M": "6 months",
  "1Y": "1 year",
  "2Y": "2 years",
};

export const RANGE_MONTHS: Record<Exclude<StatsRange, "1W">, number> = {
  M: 1,
  "3M": 3,
  "6M": 6,
  "1Y": 12,
  "2Y": 24,
};

export function isDayStatsRange(range: StatsRange): range is "1W" | "M" {
  return range === "1W" || range === "M";
}
