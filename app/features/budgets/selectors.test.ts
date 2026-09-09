import { describe, expect, it } from "vitest";
import {
  categoryLookbackSpend,
  dailyBudgetAllowance,
  globalBudgetAllocation,
  suggestedCategoryBudgetUpdates,
} from "@/features/budgets/selectors";
import type { Transaction } from "@/lib/types";

function transaction(
  id: string,
  categoryId: string,
  amount: number,
  occurredAt: number,
  category: Transaction["category"] = "Dining",
): Transaction {
  return {
    id,
    name: "Item",
    category,
    categoryId,
    time: "",
    day: "",
    amount,
    occurredAt,
  };
}

describe("categoryLookbackSpend", () => {
  it("sums the last six calendar months and averages monthly", () => {
    const now = new Date(2026, 6, 11);
    const rows = [
      transaction("a", "dining", 300, new Date(2026, 6, 2).getTime()),
      transaction("b", "dining", 900, new Date(2026, 1, 10).getTime()),
      transaction("c", "dining", 50, new Date(2025, 11, 20).getTime()),
      transaction("d", "other", 999, new Date(2026, 6, 2).getTime()),
    ];

    expect(categoryLookbackSpend(rows, "dining", 6, now)).toEqual({
      total: 1200,
      monthlyAverage: 200,
      monthCount: 6,
    });
  });
});

describe("suggestedCategoryBudgetUpdates", () => {
  it("returns categories whose suggested average differs from the current budget", () => {
    const now = new Date(2026, 6, 11);
    const rows = [
      transaction("a", "dining", 300, new Date(2026, 6, 2).getTime()),
      transaction("b", "dining", 900, new Date(2026, 1, 10).getTime()),
      transaction("c", "bills", 600, new Date(2026, 6, 2).getTime(), "Bills"),
    ];

    expect(
      suggestedCategoryBudgetUpdates(
        rows,
        [
          { id: "dining", name: "Dining", monthlyBudgetMinor: null },
          { id: "bills", name: "Bills", monthlyBudgetMinor: 50_000 },
          { id: "empty", name: "Groceries", monthlyBudgetMinor: null },
        ],
        6,
        now,
      ),
    ).toEqual([
      { id: "dining", name: "Dining", suggestedLimit: 200, currentLimit: null },
      { id: "bills", name: "Bills", suggestedLimit: 100, currentLimit: 500 },
    ]);
  });
});

describe("dailyBudgetAllowance", () => {
  const totals = {
    totalSpent: 700,
    totalLimit: 1_000,
    pct: 70,
    left: 300,
    over: false,
  };

  it("spreads the remaining budget across the rest of the month including today", () => {
    expect(dailyBudgetAllowance(totals, new Date(2026, 7, 22, 23, 30))).toEqual({
      amount: 30,
      daysRemaining: 10,
    });
  });

  it("uses one remaining day on the last day of the month", () => {
    expect(dailyBudgetAllowance(totals, new Date(2026, 7, 31))).toEqual({
      amount: 300,
      daysRemaining: 1,
    });
  });

  it("reserves upcoming bills before dividing the remaining budget", () => {
    expect(dailyBudgetAllowance(totals, new Date(2026, 7, 22), 125)).toEqual({
      amount: 17.5,
      daysRemaining: 10,
    });
  });

  it("shows zero spendable money when upcoming bills consume or exceed the budget", () => {
    for (const upcoming of [300, 400]) {
      expect(dailyBudgetAllowance(totals, new Date(2026, 7, 22), upcoming)).toEqual({
        amount: 0,
        daysRemaining: 10,
      });
    }
  });

  it("shows a zero allowance when the budget is exactly exhausted", () => {
    expect(dailyBudgetAllowance({ ...totals, left: 0 }, new Date(2026, 7, 31))).toEqual({
      amount: 0,
      daysRemaining: 1,
    });
  });

  it("is unavailable without a budget or after the budget is exceeded", () => {
    expect(dailyBudgetAllowance({ ...totals, totalLimit: 0 }, new Date(2026, 7, 22))).toBeNull();
    expect(dailyBudgetAllowance({ ...totals, left: -1 }, new Date(2026, 7, 22))).toBeNull();
  });
});

const categories = [
  { id: "dining", name: "Dining", sortOrder: 0, monthlyBudgetMinor: null },
  { id: "bills", name: "Bills", sortOrder: 1, monthlyBudgetMinor: 50_000 },
  { id: "empty", name: "Groceries", sortOrder: 2, monthlyBudgetMinor: 20_000 },
];

describe("globalBudgetAllocation", () => {
  it("uses six completed local calendar months and excludes both adjacent windows", () => {
    const now = new Date(2026, 7, 10, 12);
    const rows = [
      transaction("start", "dining", 100, new Date(2026, 1, 1).getTime()),
      transaction("end", "dining", 200, new Date(2026, 6, 31, 23, 59).getTime()),
      transaction("previous", "dining", 400, new Date(2026, 0, 31, 23, 59).getTime()),
      transaction("current", "dining", 800, new Date(2026, 7, 1).getTime()),
    ];

    const result = globalBudgetAllocation(rows, categories, 1_000, 6, now);

    expect(result.window).toEqual({
      start: new Date(2026, 1, 1).getTime(),
      end: new Date(2026, 7, 1).getTime(),
      monthCount: 6,
    });
    expect(result.sixMonthSpend).toBe(300);
    expect(result.allocations[0]).toMatchObject({
      id: "dining",
      sixMonthSpend: 300,
      monthlyAverage: 50,
      allocatedLimit: 1_000,
    });
  });

  it("handles completed-month windows across a leap-year boundary", () => {
    const now = new Date(2024, 2, 15);
    const rows = [
      transaction("leap", "dining", 290, new Date(2024, 1, 29, 23, 59).getTime()),
      transaction("current", "dining", 999, new Date(2024, 2, 1).getTime()),
      transaction("old", "dining", 999, new Date(2023, 7, 31, 23, 59).getTime()),
    ];

    const result = globalBudgetAllocation(rows, categories, 290, 6, now);

    expect(result.window.start).toBe(new Date(2023, 8, 1).getTime());
    expect(result.window.end).toBe(new Date(2024, 2, 1).getTime());
    expect(result.sixMonthSpend).toBe(290);
  });

  it("groups by stable category id and ignores a renamed display label", () => {
    const now = new Date(2026, 7, 10);
    const rows = [
      transaction("old-name", "dining", 300, new Date(2026, 5, 1).getTime(), "Eating Out"),
      transaction("new-name", "dining", 300, new Date(2026, 6, 1).getTime(), "Dining"),
    ];

    const result = globalBudgetAllocation(rows, categories, 600, 6, now);

    expect(result.allocations.find((allocation) => allocation.id === "dining")).toMatchObject({
      sixMonthSpend: 600,
      allocatedLimit: 600,
    });
  });

  it("splits proportionally and uses largest remainders to preserve the exact total", () => {
    const now = new Date(2026, 7, 10);
    const rows = [
      transaction("dining", "dining", 200, new Date(2026, 6, 1).getTime()),
      transaction("bills", "bills", 100, new Date(2026, 6, 1).getTime(), "Bills"),
    ];

    const result = globalBudgetAllocation(rows, categories, 100, 6, now);

    expect(result.canApply).toBe(true);
    expect(result.totalAllocated).toBe(100);
    expect(result.allocations.map(({ id, share, allocatedLimit }) => ({
      id,
      share,
      allocatedLimit,
    }))).toEqual([
      { id: "dining", share: 67, allocatedLimit: 67 },
      { id: "bills", share: 33, allocatedLimit: 33 },
      { id: "empty", share: 0, allocatedLimit: null },
    ]);
  });

  it("breaks equal remainder ties by sort order and then category id", () => {
    const now = new Date(2026, 7, 10);
    const rows = [
      transaction("a", "a", 1, new Date(2026, 6, 1).getTime()),
      transaction("b", "b", 1, new Date(2026, 6, 1).getTime()),
      transaction("c", "c", 1, new Date(2026, 6, 1).getTime()),
    ];
    const tied = [
      { id: "b", name: "B", sortOrder: 1, monthlyBudgetMinor: null },
      { id: "a", name: "A", sortOrder: 1, monthlyBudgetMinor: null },
      { id: "c", name: "C", sortOrder: 0, monthlyBudgetMinor: null },
    ];

    const result = globalBudgetAllocation(rows, tied, 2, 6, now);

    expect(Object.fromEntries(
      result.allocations.map((allocation) => [allocation.id, allocation.allocatedLimit]),
    )).toEqual({ a: 1, b: 0, c: 1 });
  });

  it("clears zero-history categories and reports all-zero history", () => {
    const now = new Date(2026, 7, 10);
    const partial = globalBudgetAllocation(
      [transaction("dining", "dining", 100, new Date(2026, 6, 1).getTime())],
      categories,
      500,
      6,
      now,
    );
    const empty = globalBudgetAllocation([], categories, 500, 6, now);

    expect(partial.allocations.find((allocation) => allocation.id === "empty")).toMatchObject({
      currentLimit: 200,
      allocatedLimit: null,
    });
    expect(empty).toMatchObject({ issue: "no-history", canApply: false, totalAllocated: 0 });
  });

  it("marks matching allocations unchanged and keeps rounded zero distinct from no history", () => {
    const now = new Date(2026, 7, 10);
    const rows = [
      transaction("large", "dining", 100, new Date(2026, 6, 1).getTime()),
      transaction("small", "bills", 1, new Date(2026, 6, 1).getTime(), "Bills"),
    ];
    const matching = [
      { id: "dining", name: "Dining", sortOrder: 0, monthlyBudgetMinor: 100 },
      { id: "bills", name: "Bills", sortOrder: 1, monthlyBudgetMinor: 0 },
      { id: "empty", name: "Groceries", sortOrder: 2, monthlyBudgetMinor: null },
    ];

    const result = globalBudgetAllocation(rows, matching, 1, 6, now);

    expect(result.allocations.map(({ id, allocatedLimit, changed }) => ({
      id,
      allocatedLimit,
      changed,
    }))).toEqual([
      { id: "dining", allocatedLimit: 1, changed: false },
      { id: "bills", allocatedLimit: 0, changed: false },
      { id: "empty", allocatedLimit: null, changed: false },
    ]);
  });

  it.each([0, -1, 1.5, Number.NaN, Number.POSITIVE_INFINITY])(
    "rejects an invalid global total of %s",
    (total) => {
      const result = globalBudgetAllocation(
        [transaction("dining", "dining", 100, new Date(2026, 6, 1).getTime())],
        categories,
        total,
        6,
        new Date(2026, 7, 10),
      );

      expect(result).toMatchObject({ issue: "invalid-total", canApply: false });
    },
  );

  it("reports when no categories exist", () => {
    const result = globalBudgetAllocation([], [], 500, 6, new Date(2026, 7, 10));
    expect(result).toMatchObject({ issue: "no-categories", canApply: false });
  });
});
