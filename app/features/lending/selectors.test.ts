import { describe, expect, it } from "vitest";
import type { Lend } from "@/lib/types";
import {
  groupLendsByDay,
  lendContactSummaries,
  lendingTotals,
  signedLendAmount,
} from "@/features/lending/selectors";

const lend = (patch: Partial<Lend> & Pick<Lend, "id">): Lend => ({
  contactName: "Ari",
  contactId: "contact-ari",
  amount: 100,
  amountMinor: 10_000,
  occurredAt: 1,
  comment: "",
  kind: "lent",
  time: "10:00 AM",
  day: "Today",
  ...patch,
});

describe("lending selectors", () => {
  it("nets repayments and omits fully settled contacts", () => {
    const rows = [
      lend({ id: "lent-ari", amount: 500 }),
      lend({ id: "back-ari", amount: 200, kind: "repaid", occurredAt: 2 }),
      lend({ id: "lent-bea", contactName: "Bea", contactId: "contact-bea", amount: 50 }),
      lend({
        id: "back-bea",
        contactName: "Bea",
        contactId: "contact-bea",
        amount: 50,
        kind: "repaid",
        occurredAt: 3,
      }),
    ];

    expect(lendContactSummaries(rows)).toMatchObject([
      { contactName: "Ari", balance: 300, magnitude: 300, direction: "owedToMe", entryCount: 2 },
    ]);
    expect(lendingTotals(lendContactSummaries(rows))).toEqual({
      owedToMe: 300,
      iOwe: 0,
      net: 300,
    });
  });

  it("keeps borrowings as a negative balance the user owes", () => {
    const rows = [
      lend({ id: "borrowed", amount: 400, kind: "borrowed" }),
      lend({ id: "paid-back", amount: 150, kind: "returned", occurredAt: 2 }),
    ];

    expect(lendContactSummaries(rows)).toMatchObject([
      { contactName: "Ari", balance: -250, magnitude: 250, direction: "iOwe", entryCount: 2 },
    ]);
    expect(lendingTotals(lendContactSummaries(rows))).toEqual({
      owedToMe: 0,
      iOwe: 250,
      net: -250,
    });
  });

  it("omits contacts that net to zero in either direction", () => {
    const rows = [
      lend({ id: "borrowed", amount: 100, kind: "borrowed" }),
      lend({ id: "paid-back", amount: 100, kind: "returned", occurredAt: 2 }),
      lend({ id: "lent-bea", contactName: "Bea", contactId: "contact-bea", amount: 50 }),
      lend({
        id: "back-bea",
        contactName: "Bea",
        contactId: "contact-bea",
        amount: 50,
        kind: "repaid",
        occurredAt: 3,
      }),
    ];

    expect(lendContactSummaries(rows)).toEqual([]);
  });

  it("nets a contact both lent to and borrowed from onto one side only", () => {
    const rows = [
      lend({ id: "lent-ari", amount: 100 }),
      lend({ id: "borrowed-ari", amount: 30, kind: "borrowed", occurredAt: 2 }),
      lend({
        id: "borrowed-bea",
        contactName: "Bea",
        contactId: "contact-bea",
        amount: 45,
        kind: "borrowed",
      }),
    ];

    expect(lendingTotals(lendContactSummaries(rows))).toEqual({
      owedToMe: 70,
      iOwe: 45,
      net: 25,
    });
  });

  it("sorts summaries by balance size regardless of direction", () => {
    const rows = [
      lend({ id: "small", amount: 20 }),
      lend({ id: "big", contactName: "Bea", contactId: "contact-bea", amount: 90, kind: "borrowed" }),
      lend({ id: "mid", contactName: "Cal", contactId: "contact-cal", amount: 50 }),
    ];

    expect(lendContactSummaries(rows).map((row) => row.contactId)).toEqual([
      "contact-bea",
      "contact-cal",
      "contact-ari",
    ]);
  });

  it("signs each direction by which way the money moved", () => {
    expect(signedLendAmount(lend({ id: "a", kind: "lent" }))).toBe(100);
    expect(signedLendAmount(lend({ id: "b", kind: "repaid" }))).toBe(-100);
    expect(signedLendAmount(lend({ id: "c", kind: "borrowed" }))).toBe(-100);
    expect(signedLendAmount(lend({ id: "d", kind: "returned" }))).toBe(100);
  });

  it("groups newest-first activity by day and calculates the daily net", () => {
    const rows = [
      lend({ id: "old", occurredAt: 1, day: "Yesterday", amount: 60 }),
      lend({ id: "new", occurredAt: 3, amount: 100 }),
      lend({ id: "back", occurredAt: 2, amount: 30, kind: "repaid" }),
    ];

    expect(groupLendsByDay(rows)).toMatchObject([
      { label: "Today", netAmount: 70, items: [{ id: "new" }, { id: "back" }] },
      { label: "Yesterday", netAmount: 60, items: [{ id: "old" }] },
    ]);
  });
});
