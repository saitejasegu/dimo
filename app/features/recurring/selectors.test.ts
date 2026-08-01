import { describe, expect, it } from "vitest";
import type { Recurring, Transaction } from "@/lib/types";
import { allUpcomingBills, upcomingBills } from "@/features/recurring/selectors";

function recurring(id: string, anchorDate: string, paused = false): Recurring {
  return {
    id,
    name: id,
    category: "Subscriptions",
    due: "",
    amount: 10,
    paused,
    anchorDate,
    frequency: "monthly",
  };
}

/** A materialized occurrence transaction, keyed as the backend cron writes it. */
function occurrence(recId: string, dateKey: string): Transaction {
  return {
    id: `recurring:${recId}:${dateKey}`,
    name: recId,
    category: "Subscriptions",
    time: "12:00 PM",
    day: "Today",
    amount: 10,
  };
}

describe("upcomingBills", () => {
  it("returns every active bill due in the current month when uncapped", () => {
    const now = new Date(2026, 6, 12);
    const result = upcomingBills(
      [
        recurring("fifth", "2026-07-28"),
        recurring("first", "2026-07-13"),
        recurring("fourth", "2026-07-24"),
        recurring("second", "2026-07-15"),
        recurring("third", "2026-07-20"),
        recurring("paused", "2026-07-14", true),
        recurring("next-month", "2026-08-01"),
      ],
      [],
      undefined,
      now,
    );

    expect(result.map((item) => item.id)).toEqual([
      "first",
      "second",
      "third",
      "fourth",
      "fifth",
    ]);
  });

  it("still supports a display limit", () => {
    const now = new Date(2026, 6, 12);
    const result = upcomingBills(
      [
        recurring("third", "2026-07-20"),
        recurring("first", "2026-07-13"),
        recurring("second", "2026-07-15"),
      ],
      [],
      2,
      now,
    );
    expect(result.map((item) => item.id)).toEqual(["first", "second"]);
  });

  it("drops a bill once its due occurrence has been charged this month", () => {
    // "today" is the bill's own anchor day, so nextOccurrence is today.
    const now = new Date(2026, 6, 24);
    const bill = recurring("icloud", "2026-07-24");

    expect(upcomingBills([bill], [], undefined, now).map((b) => b.id)).toEqual([
      "icloud",
    ]);
    expect(
      upcomingBills([bill], [occurrence("icloud", "2026-07-24")], undefined, now),
    ).toEqual([]);
  });
});

describe("allUpcomingBills", () => {
  it("returns active and paused bills sorted by next due date", () => {
    const now = new Date(2026, 6, 12);
    const result = allUpcomingBills(
      [
        recurring("next-month", "2026-08-01"),
        recurring("first", "2026-07-13"),
        recurring("paused", "2026-07-14", true),
        recurring("second", "2026-07-15"),
      ],
      [],
      now,
    );

    expect(result.map((item) => item.id)).toEqual(["first", "paused", "second", "next-month"]);
  });

  it("advances a charged bill to its next occurrence", () => {
    const now = new Date(2026, 6, 24);
    const bill = recurring("icloud", "2026-07-24");
    // With July charged, the next due date rolls to August, not this month.
    const result = allUpcomingBills([bill], [occurrence("icloud", "2026-07-24")], now);
    expect(result.map((item) => item.id)).toEqual(["icloud"]);
    expect(upcomingBills([bill], [occurrence("icloud", "2026-07-24")], undefined, now)).toEqual([]);
  });

  it("keeps paused-only accounts manageable from Home", () => {
    const now = new Date(2026, 6, 12);
    const paused = recurring("paused", "2026-09-01", true);

    expect(upcomingBills([paused], [], undefined, now)).toEqual([]);
    expect(allUpcomingBills([paused], [], now)).toEqual([paused]);
  });
});
