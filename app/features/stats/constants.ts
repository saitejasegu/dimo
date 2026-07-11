import type { CategoryName, StatsRange } from "@/lib/types";

export interface MonthPoint {
  label: string;
  amount: number;
  now?: boolean;
}

/** Trailing 11 months of history; the current month (Jul) is appended live. */
export const STATS_HISTORY: MonthPoint[] = [
  { label: "Aug", amount: 7200 },
  { label: "Sep", amount: 6800 },
  { label: "Oct", amount: 9800 },
  { label: "Nov", amount: 8900 },
  { label: "Dec", amount: 11400 },
  { label: "Jan", amount: 7600 },
  { label: "Feb", amount: 6100 },
  { label: "Mar", amount: 7800 },
  { label: "Apr", amount: 6900 },
  { label: "May", amount: 9200 },
  { label: "Jun", amount: 8400 },
];

export const RANGE_MONTHS: Record<StatsRange, number> = {
  M: 1,
  "3M": 3,
  "6M": 6,
  "1Y": 12,
};

export const RANGE_LABEL: Record<StatsRange, string> = {
  M: "July",
  "3M": "3M",
  "6M": "6M",
  "1Y": "1Y",
};

export const SPENT_LABEL: Record<StatsRange, string> = {
  M: "Spent in July",
  "3M": "Spent · May – Jul",
  "6M": "Spent · Feb – Jul",
  "1Y": "Spent · Aug 2025 – Jul 2026",
};

/** Denominator (days) used to compute the average-per-day caption. */
export const RANGE_DAYS: Record<StatsRange, number> = {
  M: 8,
  "3M": 69,
  "6M": 158,
  "1Y": 365,
};

export const PERIOD_NAME: Record<StatsRange, string> = {
  M: "July",
  "3M": "3 months",
  "6M": "6 months",
  "1Y": "year",
};

/** Synthetic historical category distribution for ranges beyond a month. */
export const CATEGORY_SHARES: Record<CategoryName, number> = {
  Groceries: 0.3,
  Dining: 0.22,
  Bills: 0.16,
  Transit: 0.13,
  Shopping: 0.19,
};

/** [amount, count] merchant history added for wider ranges. */
export const MERCHANT_EXTRAS: Record<
  StatsRange,
  Record<string, [number, number]>
> = {
  M: {},
  "3M": {
    Swiggy: [2600, 7],
    BigBasket: [3400, 4],
    Uber: [900, 5],
    Netflix: [1298, 2],
    Zomato: [1850, 5],
    Amazon: [2400, 3],
  },
  "6M": {
    Swiggy: [5400, 14],
    BigBasket: [7800, 9],
    Uber: [2100, 11],
    Netflix: [3245, 5],
    Zomato: [4100, 11],
    Amazon: [6200, 7],
  },
  "1Y": {
    Swiggy: [11200, 29],
    BigBasket: [15600, 18],
    Uber: [4100, 22],
    Netflix: [7139, 11],
    Zomato: [8300, 21],
    Amazon: [12800, 14],
  },
};

export const STATS_RANGES: StatsRange[] = ["M", "3M", "6M", "1Y"];
