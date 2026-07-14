import { describe, expect, it } from "vitest";
import {
  localDateTimeTimestamp,
  localTimeKey,
  nextOccurrence,
  occurrencesThrough,
} from "@/lib/dates";

describe("localDateTimeTimestamp", () => {
  it("combines a local date and time into epoch ms", () => {
    const now = new Date(2026, 6, 15, 18, 0, 0);
    expect(localDateTimeTimestamp("2026-07-10", "09:30", now)).toBe(
      new Date(2026, 6, 10, 9, 30, 0, 0).getTime(),
    );
  });

  it("caps future datetimes at now", () => {
    const now = new Date(2026, 6, 15, 12, 0, 0);
    expect(localDateTimeTimestamp("2026-07-15", "18:00", now)).toBe(now.getTime());
  });

  it("falls back to now when the date is missing", () => {
    const now = new Date(2026, 6, 15, 12, 0, 0);
    expect(localDateTimeTimestamp("", "09:30", now)).toBe(now.getTime());
  });
});

describe("localTimeKey", () => {
  it("formats hours and minutes as HH:mm", () => {
    expect(localTimeKey(new Date(2026, 6, 15, 9, 5, 30))).toBe("09:05");
  });
});

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
