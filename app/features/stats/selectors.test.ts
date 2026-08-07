import { describe, expect, it } from "vitest";
import {
  dayBars,
  hasEarlierData,
  monthBars,
  periodLabel,
  rangeStart,
  statsAnchor,
  statsScope,
  topMerchants,
  trendBars,
} from "@/features/stats/selectors";
import type { Transaction } from "@/lib/types";
import { createInitialState } from "@/store/state";

const monthYearLabel = (date: Date) =>
  new Intl.DateTimeFormat(undefined, { month: "short", year: "numeric" }).format(date);

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

  it("averages from the oldest transaction date in the selected range", () => {
    const now = new Date(2026, 6, 11, 15);
    const rows = [
      transaction("oldest", 100, new Date(2026, 6, 7, 23).getTime()),
      transaction("today", 400, new Date(2026, 6, 11, 10).getTime()),
      transaction("outside-range", 999, new Date(2025, 6, 1).getTime()),
    ];

    expect(statsScope("1Y", rows, now).averageLabel).toBe("₹100 avg per day");
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

describe("previous stats periods", () => {
  const now = new Date(2026, 6, 11, 15);

  it("keeps the current period anchored to now at offset 0", () => {
    expect(statsAnchor("3M", 0, now)).toBe(now);
    expect(rangeStart("3M", statsAnchor("3M", 0, now))).toEqual(new Date(2026, 4, 1));
  });

  it("steps back a full range and stays contiguous", () => {
    // 3M current window is 1 May - 11 Jul, so the previous one is 1 Feb - 30 Apr.
    const anchor = statsAnchor("3M", -1, now);
    expect(anchor).toEqual(new Date(2026, 3, 30, 23, 59, 59, 999));
    expect(rangeStart("3M", anchor)).toEqual(new Date(2026, 1, 1));

    const older = statsAnchor("3M", -2, now);
    expect(rangeStart("3M", older)).toEqual(new Date(2025, 10, 1));
  });

  it("scopes totals and bars to the previous period", () => {
    const rows = [
      transaction("current", 100, new Date(2026, 6, 2).getTime()),
      transaction("previous", 50, new Date(2026, 2, 4).getTime()),
      transaction("older-still", 999, new Date(2025, 0, 1).getTime()),
    ];

    expect(statsScope("3M", rows, now, 0).scopeTotal).toBe(100);
    expect(statsScope("3M", rows, now, -1).scopeTotal).toBe(50);

    const bars = trendBars("3M", statsScope("3M", rows, now, -1).transactions, null, now, -1);
    expect(bars.bars).toHaveLength(3);
    expect(bars.bars.map((bar) => bar.amount)).toEqual([0, 50, 0]);
    expect(bars.bars.map((bar) => bar.key)).toEqual(["2026-1", "2026-2", "2026-3"]);
  });

  it("steps a week back with seven day bars and no overlap", () => {
    const anchor = statsAnchor("1W", -1, now);
    expect(anchor).toEqual(new Date(2026, 6, 4, 23, 59, 59, 999));
    expect(rangeStart("1W", anchor)).toEqual(new Date(2026, 5, 28));

    const bars = trendBars("1W", [], null, now, -1);
    expect(bars.bars).toHaveLength(7);
    // Current week starts the day after the previous window ends.
    expect(rangeStart("1W", now)).toEqual(new Date(2026, 6, 5));
  });

  it("labels past periods instead of claiming they are current", () => {
    expect(statsScope("M", [], now, 0).spentLabel).toBe("Spent this month");
    expect(statsScope("M", [], now, 0).periodLabel).toBe("This month");
    expect(periodLabel("M", -1, now)).toBe(monthYearLabel(new Date(2026, 5, 1)));
    expect(statsScope("M", [], now, -1).spentLabel).toBe(
      `Spent in ${periodLabel("M", -1, now)}`,
    );
    expect(periodLabel("3M", -1, now)).toContain("–");
  });

  it("reports whether earlier data exists so previous can stop", () => {
    const rows = [transaction("only", 10, new Date(2026, 6, 2).getTime())];
    expect(hasEarlierData(rows, "3M", 0, now)).toBe(false);

    const withHistory = [...rows, transaction("old", 5, new Date(2025, 0, 1).getTime())];
    expect(hasEarlierData(withHistory, "3M", 0, now)).toBe(true);
    // Offset -6 starts 1 Nov 2024, which predates the oldest row.
    expect(hasEarlierData(withHistory, "3M", -6, now)).toBe(false);
  });
});
