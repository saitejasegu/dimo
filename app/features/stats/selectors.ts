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

export function rangeStart(range: StatsRange, now = new Date()): Date {
  if (range === "1W") {
    return startOfLocalDay(new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6));
  }
  return monthStart(now, -(RANGE_MONTHS[range] - 1));
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
  averageLabel: string;
  transactions: Transaction[];
}

export function statsScope(range: StatsRange, transactions: Transaction[], now = new Date()): StatsScope {
  const scoped = inRange(transactions, range, now);
  const scopeTotal = scoped.reduce((sum, t) => sum + t.amount, 0);
  const start = rangeStart(range, now);
  const days = Math.max(1, Math.floor((now.getTime() - start.getTime()) / 86_400_000) + 1);
  const spentLabel =
    range === "1W"
      ? "Spent this week"
      : range === "M"
        ? "Spent this month"
        : `Spent in the last ${RANGE_MONTHS[range]} months`;
  return {
    rangeMonths: range === "1W" ? 0 : RANGE_MONTHS[range],
    scopeTotal,
    scopePast: 0,
    spentLabel,
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
      label:
        range === "1W"
          ? cursor.toLocaleDateString(undefined, { weekday: "short" })
          : String(cursor.getDate()),
      captionLabel: cursor.toLocaleDateString(undefined, { month: "short", day: "numeric" }),
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
  const entries = Array.from({ length: count }, (_, index) => {
    const date = monthStart(now, index - count + 1);
    const key = `${date.getFullYear()}-${date.getMonth()}`;
    const amount = transactions
      .filter((t) => {
        const d = new Date(t.occurredAt ?? 0);
        return `${d.getFullYear()}-${d.getMonth()}` === key;
      })
      .reduce((sum, t) => sum + t.amount, 0);
    const label = date.toLocaleDateString(undefined, { month: "short" });
    return { key, label, captionLabel: label, amount };
  });

  return buildBars("By month", entries, selectedMonth, count > 6);
}

export function trendBars(
  range: StatsRange,
  transactions: Transaction[],
  selectedKey: string | null,
  now = new Date(),
): MonthBars {
  return isDayStatsRange(range)
    ? dayBars(range, transactions, selectedKey, now)
    : monthBars(range, transactions, selectedKey, now);
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
