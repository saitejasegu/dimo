import { describe, expect, it } from "vitest";
import { categoryLookbackSpend } from "@/features/budgets/selectors";
import type { Transaction } from "@/lib/types";

function transaction(
  id: string,
  categoryId: string,
  amount: number,
  occurredAt: number,
): Transaction {
  return {
    id,
    name: "Item",
    category: "Dining",
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
