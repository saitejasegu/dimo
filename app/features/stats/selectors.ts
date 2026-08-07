import type { CategoryName, StatsRange, Transaction } from "@/lib/types";
import { compactMoney, money, percent } from "@/lib/format";
import { localDateKey } from "@/lib/dates";
import { isDayStatsRange, RANGE_MONTHS } from "@/features/stats/constants";

function monthStart(date: Date, offset = 0) {
  return new Date(date.getFullYear(), date.getMonth() + offset, 1);
}

function startOfLocalDay(date: Date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function endOfLocalDay(date: Date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 23, 59, 59, 999);
}

function inclusiveLocalDayCount(start: Date, end: Date) {
  const startDay = Date.UTC(start.getFullYear(), start.getMonth(), start.getDate());
  const endDay = Date.UTC(end.getFullYear(), end.getMonth(), end.getDate());
  return Math.max(1, Math.floor((endDay - startDay) / 86_400_000) + 1);
}

export function rangeStart(range: StatsRange, now = new Date()): Date {
  if (range === "1W") {
    return startOfLocalDay(new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6));
  }
  return monthStart(now, -(RANGE_MONTHS[range] - 1));
}

/**
 * Effective "now" for a period `offset` steps back — 0 is the current period,
 * -1 is one full range back. Every window function already derives its bounds
 * from `now`, so shifting this one value moves the scope, the bars, and the
 * average denominator together. Periods are contiguous and never overlap.
 */
export function statsAnchor(range: StatsRange, offset: number, now = new Date()): Date {
  // The current period stays partial: it ends at this instant, not month end.
  if (offset === 0) return now;
  if (range === "1W") {
    const day = startOfLocalDay(now);
    return endOfLocalDay(new Date(day.getFullYear(), day.getMonth(), day.getDate() + offset * 7));
  }
  const shifted = monthStart(now, offset * RANGE_MONTHS[range]);
  // Day 0 of the following month is the last day of `shifted`'s month.
  return new Date(shifted.getFullYear(), shifted.getMonth() + 1, 0, 23, 59, 59, 999);
}

/** Human label for the window a given offset selects. */
export function periodLabel(range: StatsRange, offset: number, now = new Date()): string {
  if (offset === 0) {
    if (range === "1W") return "This week";
    if (range === "M") return "This month";
    return `Last ${RANGE_MONTHS[range]} months`;
  }
  const anchor = statsAnchor(range, offset, now);
  const start = rangeStart(range, anchor);
  if (range === "1W") {
    return `${monthDayFormat.format(start)} – ${monthDayFormat.format(anchor)}`;
  }
  if (RANGE_MONTHS[range] === 1) return monthYearFormat.format(anchor);
  return `${monthYearFormat.format(start)} – ${monthYearFormat.format(anchor)}`;
}

/** Whether anything predates the selected window, so "previous" can be disabled. */
export function hasEarlierData(
  transactions: Transaction[],
  range: StatsRange,
  offset: number,
  now = new Date(),
): boolean {
  const start = rangeStart(range, statsAnchor(range, offset, now)).getTime();
  return transactions.some((transaction) => (transaction.occurredAt ?? 0) < start);
}

function inRange(transactions: Transaction[], range: StatsRange, now = new Date()) {
  const start = rangeStart(range, now).getTime();
  return transactions.filter((t) => (t.occurredAt ?? 0) >= start && (t.occurredAt ?? 0) <= now.getTime());
}

export interface StatsScope {
  rangeMonths: number;
  scopeTotal: number;
  scopePast: number;
  spentLabel: string;
  periodLabel: string;
  averageLabel: string;
  transactions: Transaction[];
}

export function statsScope(
  range: StatsRange,
  transactions: Transaction[],
  now = new Date(),
  offset = 0,
): StatsScope {
  // Everything below is anchored here, so a past period shifts as one piece.
  const anchor = statsAnchor(range, offset, now);
  const scoped = inRange(transactions, range, anchor);
  const scopeTotal = scoped.reduce((sum, t) => sum + t.amount, 0);
  const oldestTimestamp = scoped.reduce<number | null>((oldest, transaction) => {
    const occurredAt = transaction.occurredAt ?? 0;
    return oldest === null || occurredAt < oldest ? occurredAt : oldest;
  }, null);
  const days =
    oldestTimestamp === null ? 1 : inclusiveLocalDayCount(new Date(oldestTimestamp), anchor);
  const label = periodLabel(range, offset, now);
  const spentLabel =
    offset !== 0
      ? `Spent in ${label}`
      : range === "1W"
        ? "Spent this week"
        : range === "M"
          ? "Spent this month"
          : `Spent in the last ${RANGE_MONTHS[range]} months`;
  return {
    rangeMonths: range === "1W" ? 0 : RANGE_MONTHS[range],
    scopeTotal,
    scopePast: 0,
    spentLabel,
    periodLabel: label,
    averageLabel: `${money(scopeTotal / days)} avg per day`,
    transactions: scoped,
  };
}

export interface MonthBar {
  key: string;
  label: string;
  amount: number;
  display: string;
  selected: boolean;
  heightRatio: number;
  wide: boolean;
}

export interface MonthBars {
  visible: boolean;
  title: string;
  caption: string;
  bars: MonthBar[];
}

function buildBars(
  title: string,
  entries: Array<{ key: string; label: string; captionLabel: string; amount: number }>,
  selectedKey: string | null,
  wide: boolean,
): MonthBars {
  if (entries.length === 0) return { visible: false, title, caption: "", bars: [] };
  const resolvedKey = entries.find((entry) => entry.key === selectedKey)?.key ?? entries.at(-1)!.key;
  const selected = entries.find((entry) => entry.key === resolvedKey)!;
  const max = Math.max(1, ...entries.map((entry) => entry.amount));
  return {
    visible: true,
    title,
    caption: `${selected.captionLabel}: ${money(selected.amount)}`,
    bars: entries.map((entry) => ({
      key: entry.key,
      label: entry.label,
      amount: entry.amount,
      display: !wide || entry.key === resolvedKey ? compactMoney(entry.amount) : "",
      selected: entry.key === resolvedKey,
      heightRatio: entry.amount / max,
      wide,
    })),
  };
}

/** Cached: chart labels are rebuilt on every range change and every hydrate. */
const weekdayFormat = new Intl.DateTimeFormat(undefined, { weekday: "short" });
const monthDayFormat = new Intl.DateTimeFormat(undefined, {
  month: "short",
  day: "numeric",
});
const monthFormat = new Intl.DateTimeFormat(undefined, { month: "short" });
const monthYearFormat = new Intl.DateTimeFormat(undefined, {
  month: "short",
  year: "numeric",
});

export function dayBars(
  range: StatsRange,
  transactions: Transaction[],
  selectedDay: string | null,
  now = new Date(),
): MonthBars {
  if (!isDayStatsRange(range)) return { visible: false, title: "By day", caption: "", bars: [] };

  const start = rangeStart(range, now);
  const end = startOfLocalDay(now);
  const amounts = new Map<string, number>();
  for (const transaction of transactions) {
    const key = localDateKey(new Date(transaction.occurredAt ?? 0));
    amounts.set(key, (amounts.get(key) ?? 0) + transaction.amount);
  }

  const entries: Array<{ key: string; label: string; captionLabel: string; amount: number }> = [];
  for (
    let cursor = new Date(start.getFullYear(), start.getMonth(), start.getDate());
    cursor.getTime() <= end.getTime();
    cursor = new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + 1)
  ) {
    const key = localDateKey(cursor);
    entries.push({
      key,
      label: range === "1W" ? weekdayFormat.format(cursor) : String(cursor.getDate()),
      captionLabel: monthDayFormat.format(cursor),
      amount: amounts.get(key) ?? 0,
    });
  }

  return buildBars("By day", entries, selectedDay, entries.length > 7);
}

export function monthBars(
  range: StatsRange,
  transactions: Transaction[],
  selectedMonth: string | null,
  now = new Date(),
): MonthBars {
  if (isDayStatsRange(range)) return { visible: false, title: "By month", caption: "", bars: [] };

  const count = RANGE_MONTHS[range];
  // Single grouping pass. Filtering the whole list once per month made this
  // O(months × transactions) with a `new Date()` per transaction per month.
  const amounts = new Map<string, number>();
  for (const transaction of transactions) {
    const date = new Date(transaction.occurredAt ?? 0);
    const key = `${date.getFullYear()}-${date.getMonth()}`;
    amounts.set(key, (amounts.get(key) ?? 0) + transaction.amount);
  }

  const entries = Array.from({ length: count }, (_, index) => {
    const date = monthStart(now, index - count + 1);
    const key = `${date.getFullYear()}-${date.getMonth()}`;
    const label = monthFormat.format(date);
    return { key, label, captionLabel: label, amount: amounts.get(key) ?? 0 };
  });

  return buildBars("By month", entries, selectedMonth, count > 6);
}

export function trendBars(
  range: StatsRange,
  transactions: Transaction[],
  selectedKey: string | null,
  now = new Date(),
  offset = 0,
): MonthBars {
  const anchor = statsAnchor(range, offset, now);
  return isDayStatsRange(range)
    ? dayBars(range, transactions, selectedKey, anchor)
    : monthBars(range, transactions, selectedKey, anchor);
}

export interface StatCategory {
  category: CategoryName;
  amount: number;
  caption: string;
  relative: number;
  primary: boolean;
}

export function statCategories(scope: StatsScope, limit: number): { categories: StatCategory[]; total: number } {
  const totals = new Map<string, number>();
  for (const t of scope.transactions) totals.set(t.category, (totals.get(t.category) ?? 0) + t.amount);
  const entries = [...totals].sort((a, b) => b[1] - a[1]);
  const max = entries[0]?.[1] ?? 1;
  return {
    total: entries.length,
    categories: entries
      .slice(0, Number.isFinite(limit) ? limit : undefined)
      .map(([category, amount], index) => ({
        category,
        amount,
        caption: `${money(amount)} · ${percent(amount, scope.scopeTotal)}%`,
        relative: Math.max(4, Math.round(amount / max * 100)),
        primary: index === 0,
      })),
  };
}

export interface MerchantStat {
  name: string;
  count: number;
  amount: number;
  green: boolean;
  emoji?: string;
  sub: string;
  relative: number;
}

export function topMerchants(scope: StatsScope, limit: number): { merchants: MerchantStat[]; total: number } {
  const totals = new Map<
    string,
    {
      amount: number;
      count: number;
      green: boolean;
      category: CategoryName;
      categoryEmoji?: string;
      mixedCategories: boolean;
    }
  >();
  for (const t of scope.transactions) {
    const current = totals.get(t.name) ?? {
      amount: 0,
      count: 0,
      green: false,
      category: t.category,
      categoryEmoji: t.emoji,
      mixedCategories: false,
    };
    current.amount += t.amount;
    current.count += 1;
    current.green ||= Boolean(t.green);
    current.mixedCategories ||= current.category !== t.category;
    current.categoryEmoji ??= t.emoji;
    totals.set(t.name, current);
  }
  const sorted = [...totals].sort((a, b) => b[1].amount - a[1].amount);
  const max = sorted[0]?.[1].amount ?? 1;
  return {
    total: sorted.length,
    merchants: sorted
      .slice(0, Number.isFinite(limit) ? limit : undefined)
      .map(([name, value]) => ({
        name,
        count: value.count,
        amount: value.amount,
        green: value.green,
        emoji: value.mixedCategories ? undefined : value.categoryEmoji,
        sub: `${value.count} ${value.count === 1 ? "transaction" : "transactions"} · ${percent(value.amount, scope.scopeTotal)}%`,
        relative: Math.max(6, Math.round(value.amount / max * 100)),
      })),
  };
}
