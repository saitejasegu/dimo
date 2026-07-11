import type { CategoryName, StatsRange, Transaction } from "@/lib/types";
import { compactMoney, money, percent } from "@/lib/format";
import {
  CATEGORY_SHARES,
  MERCHANT_EXTRAS,
  MonthPoint,
  PERIOD_NAME,
  RANGE_DAYS,
  RANGE_MONTHS,
  SPENT_LABEL,
  STATS_HISTORY,
} from "@/features/stats/constants";

export interface StatsScope {
  rangeMonths: number;
  scopeTotal: number;
  /** Portion of the scope total that predates the current month. */
  scopePast: number;
  spentLabel: string;
  averageLabel: string;
}

/** History plus the live current month, used for the by-month chart. */
export function buildTimeline(currentMonthSpent: number): MonthPoint[] {
  return [...STATS_HISTORY, { label: "Jul", amount: currentMonthSpent, now: true }];
}

export function statsScope(
  range: StatsRange,
  currentMonthSpent: number,
): StatsScope {
  const timeline = buildTimeline(currentMonthSpent);
  const rangeMonths = RANGE_MONTHS[range];
  const scopeTotal = timeline
    .slice(-rangeMonths)
    .reduce((sum, m) => sum + m.amount, 0);

  const average = money(Math.round(scopeTotal / RANGE_DAYS[range]));
  const averageLabel =
    `${average} avg per day` + (range === "M" ? " · Jul 1–8" : "");

  return {
    rangeMonths,
    scopeTotal,
    scopePast: scopeTotal - currentMonthSpent,
    spentLabel: SPENT_LABEL[range],
    averageLabel,
  };
}

export interface MonthBar {
  label: string;
  amount: number;
  /** Compact label shown above the bar (empty when hidden for density). */
  display: string;
  selected: boolean;
  /** Height as a fraction (0–1) of the tallest bar in the range. */
  heightRatio: number;
  /** Whether the range is dense enough to shrink bars/labels. */
  wide: boolean;
}

export interface MonthBars {
  visible: boolean;
  caption: string;
  bars: MonthBar[];
}

export function monthBars(
  range: StatsRange,
  currentMonthSpent: number,
  selectedMonth: string | null,
): MonthBars {
  if (range === "M") {
    return { visible: false, caption: "", bars: [] };
  }

  const timeline = buildTimeline(currentMonthSpent);
  const rangeMonths = RANGE_MONTHS[range];
  const months = timeline.slice(-rangeMonths);
  const max = Math.max(...months.map((m) => m.amount), 1);
  const wide = rangeMonths > 6;

  const selectedLabel =
    selectedMonth && months.some((m) => m.label === selectedMonth)
      ? selectedMonth
      : "Jul";
  const selected = months.find((m) => m.label === selectedLabel)!;

  return {
    visible: true,
    caption: `${selected.label}: ${money(selected.amount)}`,
    bars: months.map((m) => {
      const on = m.label === selectedLabel;
      return {
        label: m.label,
        amount: m.amount,
        display: on || !wide ? compactMoney(m.amount) : "",
        selected: on,
        heightRatio: m.amount / max,
        wide,
      };
    }),
  };
}

export interface StatCategory {
  category: CategoryName;
  amount: number;
  caption: string;
  /** Bar width relative to the largest category (percent). */
  relative: number;
  primary: boolean;
}

export function statCategories(
  transactions: Transaction[],
  range: StatsRange,
  scope: StatsScope,
): StatCategory[] {
  const byCategory = new Map<CategoryName, number>();
  for (const t of transactions) {
    byCategory.set(t.category, (byCategory.get(t.category) ?? 0) + t.amount);
  }

  if (range !== "M") {
    for (const category of Object.keys(CATEGORY_SHARES)) {
      const base = byCategory.get(category) ?? 0;
      byCategory.set(
        category,
        Math.round(base + CATEGORY_SHARES[category] * scope.scopePast),
      );
    }
  }

  const entries = [...byCategory.entries()].sort((a, b) => b[1] - a[1]);
  const max = entries.length ? entries[0][1] : 1;

  return entries.map(([category, amount], index) => ({
    category,
    amount,
    caption: `${money(amount)} · ${percent(amount, scope.scopeTotal)}%`,
    relative: Math.max(4, Math.round((amount / max) * 100)),
    primary: index === 0,
  }));
}

export interface MerchantStat {
  name: string;
  count: number;
  amount: number;
  green: boolean;
  sub: string;
  /** Bar width relative to the top merchant (percent). */
  relative: number;
}

interface MerchantTotals {
  amount: number;
  count: number;
  green: boolean;
}

export function topMerchants(
  transactions: Transaction[],
  range: StatsRange,
  scope: StatsScope,
  limit: number,
): { merchants: MerchantStat[]; total: number } {
  const byMerchant = new Map<string, MerchantTotals>();

  for (const t of transactions) {
    const existing = byMerchant.get(t.name);
    if (existing) {
      existing.amount += t.amount;
      existing.count += 1;
    } else {
      byMerchant.set(t.name, {
        amount: t.amount,
        count: 1,
        green: !!t.green,
      });
    }
  }

  const extras = MERCHANT_EXTRAS[range];
  for (const [name, [amount, count]] of Object.entries(extras)) {
    if (!amount) continue;
    const existing = byMerchant.get(name);
    if (existing) {
      existing.amount += amount;
      existing.count += count;
    } else {
      byMerchant.set(name, { amount, count, green: false });
    }
  }

  const sorted = [...byMerchant.entries()].sort(
    (a, b) => b[1].amount - a[1].amount,
  );
  const maxAmount = sorted.length ? sorted[0][1].amount : 1;
  const periodName = PERIOD_NAME[range];
  const take = limit >= sorted.length ? sorted.length : limit;

  const merchants = sorted.slice(0, take).map(([name, totals]) => ({
    name,
    count: totals.count,
    amount: totals.amount,
    green: totals.green,
    sub:
      `${totals.count} ${totals.count === 1 ? "transaction" : "transactions"}` +
      ` · ${percent(totals.amount, scope.scopeTotal)}% of ${periodName}`,
    relative: Math.max(6, Math.round((totals.amount / maxAmount) * 100)),
  }));

  return { merchants, total: sorted.length };
}
