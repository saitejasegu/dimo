import type { CategoryLimits, CategoryName, PaymentMethod, Transaction } from "@/lib/types";

export interface TransactionFilter {
  /** Selected category name, or "All". */
  category: CategoryName | "All";
  /** Free-text search across merchant name and category. */
  query: string;
}

export interface DayGroup {
  label: string;
  total: number;
  items: Transaction[];
}

export interface TransactionsSummary {
  total: number;
  count: number;
  largest: number;
  topCategory: CategoryName | null;
}

/** Ordered category names derived from the configured limits. */
export function categoryNames(limits: CategoryLimits): CategoryName[] {
  return Object.keys(limits);
}

/** Category names with an "All" option prepended, for filter chips. */
export function filterOptions(limits: CategoryLimits): (CategoryName | "All")[] {
  return ["All", ...categoryNames(limits)];
}

export function filterTransactions(
  transactions: Transaction[],
  filter: TransactionFilter,
): Transaction[] {
  const q = filter.query.trim().toLowerCase();

  return transactions.filter((t) => {
    const matchesCategory =
      filter.category === "All" || t.category === filter.category;
    const matchesQuery =
      !q ||
      t.name.toLowerCase().includes(q) ||
      t.category.toLowerCase().includes(q);
    return matchesCategory && matchesQuery;
  });
}

/** Group transactions into day buckets, preserving first-seen order. */
export function groupByDay(transactions: Transaction[]): DayGroup[] {
  const order: string[] = [];
  const byDay = new Map<string, Transaction[]>();

  for (const t of transactions) {
    if (!byDay.has(t.day)) {
      byDay.set(t.day, []);
      order.push(t.day);
    }
    byDay.get(t.day)!.push(t);
  }

  return order.map((day) => {
    const items = byDay.get(day)!;
    return {
      label: day,
      total: items.reduce((sum, t) => sum + t.amount, 0),
      items,
    };
  });
}

export function summarize(transactions: Transaction[]): TransactionsSummary {
  const byCategory = new Map<CategoryName, number>();
  let total = 0;
  let largest = 0;

  for (const t of transactions) {
    total += t.amount;
    largest = Math.max(largest, t.amount);
    byCategory.set(t.category, (byCategory.get(t.category) ?? 0) + t.amount);
  }

  let topCategory: CategoryName | null = null;
  let topAmount = -1;
  for (const [category, amount] of byCategory) {
    if (amount > topAmount) {
      topAmount = amount;
      topCategory = category;
    }
  }

  return { total, count: transactions.length, largest, topCategory };
}

export function totalSpent(transactions: Transaction[]): number {
  return transactions.reduce((sum, t) => sum + t.amount, 0);
}

export interface MerchantSuggestion {
  name: string;
  category: CategoryName;
  paymentMethod?: PaymentMethod;
  count: number;
}

/** Unique merchants from history matching the typed query, most-used first. */
export function merchantSuggestions(
  transactions: Transaction[],
  query: string,
  limit = 6,
): MerchantSuggestion[] {
  const q = query.trim().toLowerCase();
  if (!q) return [];

  const byKey = new Map<
    string,
    MerchantSuggestion & { occurredAt: number }
  >();

  for (const t of transactions) {
    const name = t.name.trim();
    if (!name) continue;
    const key = name.toLowerCase();
    if (!key.includes(q)) continue;

    const existing = byKey.get(key);
    const occurredAt = t.occurredAt ?? 0;
    if (!existing) {
      byKey.set(key, {
        name,
        category: t.category,
        paymentMethod: t.paymentMethod,
        count: 1,
        occurredAt,
      });
      continue;
    }

    existing.count += 1;
    if (occurredAt >= existing.occurredAt) {
      existing.name = name;
      existing.category = t.category;
      existing.paymentMethod = t.paymentMethod;
      existing.occurredAt = occurredAt;
    }
  }

  return [...byKey.values()]
    .sort((a, b) => {
      const aPrefix = a.name.toLowerCase().startsWith(q) ? 1 : 0;
      const bPrefix = b.name.toLowerCase().startsWith(q) ? 1 : 0;
      if (bPrefix !== aPrefix) return bPrefix - aPrefix;
      if (b.count !== a.count) return b.count - a.count;
      return b.occurredAt - a.occurredAt;
    })
    .slice(0, limit)
    .map(({ name, category, paymentMethod, count }) => ({
      name,
      category,
      paymentMethod,
      count,
    }));
}

