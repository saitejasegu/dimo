import { describe, expect, it } from "vitest";
import { nextOccurrence, occurrencesThrough } from "@/lib/dates";

describe("recurrence dates", () => {
  it("clamps a monthly day to the end of a short month", () => {
    const next = nextOccurrence(
      { anchorDate: "2026-01-31", frequency: "monthly" },
      new Date(2026, 1, 1),
    );
    expect([next.getFullYear(), next.getMonth(), next.getDate()]).toEqual([2026, 1, 28]);
  });

  it("uses February 28 for a leap-day yearly recurrence", () => {
    const next = nextOccurrence(
      { anchorDate: "2024-02-29", frequency: "yearly" },
      new Date(2025, 0, 1),
    );
    expect([next.getFullYear(), next.getMonth(), next.getDate()]).toEqual([2025, 1, 28]);
  });

  it("lists monthly occurrences from a past start through today", () => {
    const dates = occurrencesThrough(
      { anchorDate: "2026-01-15", frequency: "monthly" },
      new Date(2026, 3, 20),
    );
    expect(dates.map((d) => [d.getFullYear(), d.getMonth(), d.getDate()])).toEqual([
      [2026, 0, 15],
      [2026, 1, 15],
      [2026, 2, 15],
      [2026, 3, 15],
    ]);
  });

  it("returns no occurrences for a future start date", () => {
    const dates = occurrencesThrough(
      { anchorDate: "2026-08-01", frequency: "monthly" },
      new Date(2026, 3, 20),
    );
    expect(dates).toEqual([]);
  });
});
