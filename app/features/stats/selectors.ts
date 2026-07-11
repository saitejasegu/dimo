import type { CategoryName, StatsRange, Transaction } from "@/lib/types";
import { compactMoney, money, percent } from "@/lib/format";
import { RANGE_MONTHS } from "@/features/stats/constants";

function monthStart(date: Date, offset = 0) {
  return new Date(date.getFullYear(), date.getMonth() + offset, 1);
}

function inRange(transactions: Transaction[], range: StatsRange, now = new Date()) {
  const start = monthStart(now, -(RANGE_MONTHS[range] - 1)).getTime();
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
  const start = monthStart(now, -(RANGE_MONTHS[range] - 1));
  const days = Math.max(1, Math.floor((now.getTime() - start.getTime()) / 86_400_000) + 1);
  return {
    rangeMonths: RANGE_MONTHS[range],
    scopeTotal,
    scopePast: 0,
    spentLabel: range === "M" ? "Spent this month" : `Spent in the last ${RANGE_MONTHS[range]} months`,
    averageLabel: `${money(scopeTotal / days)} avg per day`,
    transactions: scoped,
  };
}

export interface MonthBar { key: string; label: string; amount: number; display: string; selected: boolean; heightRatio: number; wide: boolean; }
export interface MonthBars { visible: boolean; caption: string; bars: MonthBar[]; }

export function monthBars(range: StatsRange, transactions: Transaction[], selectedMonth: string | null, now = new Date()): MonthBars {
  if (range === "M") return { visible: false, caption: "", bars: [] };
  const count = RANGE_MONTHS[range];
  const months = Array.from({ length: count }, (_, index) => {
    const date = monthStart(now, index - count + 1);
    const key = `${date.getFullYear()}-${date.getMonth()}`;
    const amount = transactions.filter((t) => { const d = new Date(t.occurredAt ?? 0); return `${d.getFullYear()}-${d.getMonth()}` === key; }).reduce((sum, t) => sum + t.amount, 0);
    return { key, label: date.toLocaleDateString(undefined, { month: "short" }), amount };
  });
  const selectedKey = months.find((m) => m.key === selectedMonth)?.key ?? months.at(-1)!.key;
  const selected = months.find((m) => m.key === selectedKey)!;
  const max = Math.max(1, ...months.map((m) => m.amount)); const wide = count > 6;
  return { visible: true, caption: `${selected.label}: ${money(selected.amount)}`, bars: months.map((m) => ({ key: m.key, label: m.label, amount: m.amount, display: !wide || m.key === selectedKey ? compactMoney(m.amount) : "", selected: m.key === selectedKey, heightRatio: m.amount / max, wide })) };
}

export interface StatCategory { category: CategoryName; amount: number; caption: string; relative: number; primary: boolean; }
export function statCategories(scope: StatsScope): StatCategory[] {
  const totals = new Map<string, number>();
  for (const t of scope.transactions) totals.set(t.category, (totals.get(t.category) ?? 0) + t.amount);
  const entries = [...totals].sort((a, b) => b[1] - a[1]); const max = entries[0]?.[1] ?? 1;
  return entries.map(([category, amount], index) => ({ category, amount, caption: `${money(amount)} · ${percent(amount, scope.scopeTotal)}%`, relative: Math.max(4, Math.round(amount / max * 100)), primary: index === 0 }));
}

export interface MerchantStat { name: string; count: number; amount: number; green: boolean; sub: string; relative: number; }
export function topMerchants(scope: StatsScope, limit: number): { merchants: MerchantStat[]; total: number } {
  const totals = new Map<string, { amount: number; count: number; green: boolean }>();
  for (const t of scope.transactions) { const current = totals.get(t.name) ?? { amount: 0, count: 0, green: false }; current.amount += t.amount; current.count += 1; current.green ||= Boolean(t.green); totals.set(t.name, current); }
  const sorted = [...totals].sort((a, b) => b[1].amount - a[1].amount); const max = sorted[0]?.[1].amount ?? 1;
  return { total: sorted.length, merchants: sorted.slice(0, Number.isFinite(limit) ? limit : undefined).map(([name, value]) => ({ name, ...value, sub: `${value.count} ${value.count === 1 ? "transaction" : "transactions"} · ${percent(value.amount, scope.scopeTotal)}%`, relative: Math.max(6, Math.round(value.amount / max * 100)) })) };
}
