import { describe, expect, it } from "vitest";
import {
  localDateKey,
  localDateTimeTimestamp,
  localTimeKey,
  nextOccurrence,
  occurrenceTimestamp,
  occurrencesThrough,
  recurringTransactionDates,
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

  it("plans all or only the selected past occurrence", () => {
    const recurring = { anchorDate: "2026-01-15", frequency: "monthly" as const };
    const now = new Date(2026, 3, 20, 18, 0);
    expect(recurringTransactionDates(recurring, "all", now).map((date) => date.getMonth())).toEqual([0, 1, 2, 3]);
    expect(recurringTransactionDates(recurring, "selected", now).map((date) => date.getMonth())).toEqual([0]);
  });

  it("creates one transaction for monthly and yearly schedules starting today", () => {
    const now = new Date(2026, 6, 15, 18, 0);
    for (const frequency of ["monthly", "yearly"] as const) {
      const dates = recurringTransactionDates(
        { anchorDate: "2026-07-15", frequency },
        "selected",
        now,
      );
      expect(dates.map((date) => localDateKey(date))).toEqual(["2026-07-15"]);
    }
  });

  it("lists yearly occurrences for a past schedule", () => {
    const dates = recurringTransactionDates(
      { anchorDate: "2024-02-29", frequency: "yearly" },
      "all",
      new Date(2026, 2, 1),
    );
    expect(dates.map((date) => localDateKey(date))).toEqual([
      "2024-02-29",
      "2025-02-28",
      "2026-02-28",
    ]);
  });

  it("creates no transaction dates for a future schedule", () => {
    expect(recurringTransactionDates(
      { anchorDate: "2026-08-01", frequency: "yearly" },
      "selected",
      new Date(2026, 6, 15),
    )).toEqual([]);
  });

  it("preserves the selected time on generated occurrences", () => {
    const now = new Date(2026, 6, 15, 18, 0);
    expect(occurrenceTimestamp(new Date(2026, 3, 15), "09:45", now)).toBe(
      new Date(2026, 3, 15, 9, 45).getTime(),
    );
  });
});
