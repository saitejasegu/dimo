import { describe, expect, it } from "vitest";
import { monthBars, statsScope } from "@/features/stats/selectors";
import type { Transaction } from "@/lib/types";

function transaction(id: string, amount: number, occurredAt: number): Transaction {
  return { id, name: "Merchant", category: "Dining", time: "", day: "", amount, occurredAt };
}

describe("real statistics", () => {
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
});
