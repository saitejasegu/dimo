import { describe, expect, it } from "vitest";
import { monthBars, statsScope, topMerchants } from "@/features/stats/selectors";
import type { Transaction } from "@/lib/types";
import { createInitialState } from "@/store/state";

function transaction(id: string, amount: number, occurredAt: number): Transaction {
  return { id, name: "Merchant", category: "Dining", time: "", day: "", amount, occurredAt };
}

describe("real statistics", () => {
  it("defaults to one year and supports a 24-month range", () => {
    expect(createInitialState().statsRange).toBe("1Y");

    const bars = monthBars("2Y", [], null, new Date(2026, 6, 11));
    expect(bars.bars).toHaveLength(24);
  });

  it("filters the selected calendar range and includes zero months", () => {
    const now = new Date(2026, 6, 11);
    const rows = [
      transaction("current", 100, new Date(2026, 6, 2).getTime()),
      transaction("previous", 50, new Date(2026, 5, 2).getTime()),
      transaction("old", 999, new Date(2025, 0, 1).getTime()),
    ];
    expect(statsScope("3M", rows, now).scopeTotal).toBe(150);
    const bars = monthBars("3M", rows, null, now);
    expect(bars.bars).toHaveLength(3);
    expect(bars.bars.map((bar) => bar.amount)).toEqual([0, 50, 100]);
  });

  it("uses the category emoji when every merchant transaction shares a category", () => {
    const transactions = [
      { ...transaction("1", 20, 1), name: "Cafe", emoji: "🍽️" },
      { ...transaction("2", 30, 2), name: "Cafe", emoji: "🍽️" },
    ];
    const scope = { ...statsScope("M", [], new Date()), transactions, scopeTotal: 50 };

    expect(topMerchants(scope, 3).merchants[0].emoji).toBe("🍽️");
  });

  it("keeps the default emoji for merchants with mixed categories", () => {
    const transactions = [
      { ...transaction("1", 20, 1), name: "Store", emoji: "🍽️" },
      {
        ...transaction("2", 30, 2),
        name: "Store",
        category: "Groceries",
        emoji: "🛒",
      },
    ];
    const scope = { ...statsScope("M", [], new Date()), transactions, scopeTotal: 50 };

    expect(topMerchants(scope, 3).merchants[0].emoji).toBeUndefined();
  });
});
