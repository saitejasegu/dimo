import { describe, expect, it } from "vitest";
import { dayBars, monthBars, statsScope, topMerchants } from "@/features/stats/selectors";
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
    expect(bars.title).toBe("By month");
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

  it("supports a one-week range with daily bars", () => {
    const now = new Date(2026, 6, 11, 15);
    const rows = [
      transaction("today", 40, new Date(2026, 6, 11, 10).getTime()),
      transaction("yesterday", 25, new Date(2026, 6, 10, 12).getTime()),
      transaction("old", 999, new Date(2026, 6, 1).getTime()),
    ];
    expect(statsScope("1W", rows, now).scopeTotal).toBe(65);
    expect(statsScope("1W", rows, now).spentLabel).toBe("Spent this week");

    const bars = dayBars("1W", rows, null, now);
    expect(bars.visible).toBe(true);
    expect(bars.title).toBe("By day");
    expect(bars.bars).toHaveLength(7);
    expect(bars.bars.at(-1)?.amount).toBe(40);
    expect(bars.bars.at(-2)?.amount).toBe(25);
  });

  it("shows daily bars for the current month", () => {
    const now = new Date(2026, 6, 11);
    const rows = [
      transaction("early", 10, new Date(2026, 6, 1).getTime()),
      transaction("mid", 20, new Date(2026, 6, 11).getTime()),
      transaction("previous-month", 999, new Date(2026, 5, 30).getTime()),
    ];
    expect(statsScope("M", rows, now).scopeTotal).toBe(30);

    const bars = dayBars("M", rows, null, now);
    expect(bars.title).toBe("By day");
    expect(bars.bars).toHaveLength(11);
    expect(bars.bars[0]?.amount).toBe(10);
    expect(bars.bars.at(-1)?.amount).toBe(20);
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
