import { describe, expect, it } from "vitest";
import type { Lend } from "@/lib/types";
import {
  allLendContactSummaries,
  groupLendsByDay,
  lendAttribution,
  lendContactSummaries,
  lendFlow,
  lendKindFor,
  lendingTotals,
  netLendBalance,
  recentLendContacts,
  settlementKind,
  settlementLimit,
  signedLendAmount,
  unsettledLends,
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

  it("caps settlements at the balance they close and leaves openers uncapped", () => {
    const rows = [
      lend({ id: "lent", amount: 100, contactId: "r" }),
      lend({ id: "borrowed", amount: 70, contactId: "n", kind: "borrowed" }),
      lend({ id: "back", amount: 30, contactId: "r", kind: "repaid", occurredAt: 2 }),
    ];
    expect(settlementLimit("repaid", "r", rows)).toBe(70);
    expect(settlementLimit("repaid", "r", rows, "back")).toBe(100);
    expect(settlementLimit("returned", "n", rows)).toBe(70);
    expect(settlementLimit("returned", "r", rows)).toBe(0);
    expect(settlementLimit("repaid", "n", rows)).toBe(0);
    expect(settlementLimit("lent", "r", rows)).toBeNull();
    expect(settlementLimit("borrowed", "n", rows)).toBeNull();
    expect(netLendBalance("n", rows)).toBe(-70);
    expect(settlementKind("owedToMe")).toBe("repaid");
    expect(settlementKind("iOwe")).toBe("returned");
  });

  it("keeps only the current unsettled cycle", () => {
    const rows = [
      lend({ id: "a", amount: 50, occurredAt: 1 }),
      lend({ id: "b", amount: 50, kind: "repaid", occurredAt: 2 }),
      lend({ id: "c", amount: 20, occurredAt: 3 }),
      lend({ id: "d", amount: 5, kind: "repaid", occurredAt: 4 }),
    ];
    expect(unsettledLends("contact-ari", rows).map((row) => row.id)).toEqual(["c", "d"]);
  });

  it("dedupes recent contacts by id, newest first", () => {
    const rows = [
      lend({ id: "1", contactId: "a", contactName: "A", occurredAt: 1 }),
      lend({ id: "2", contactId: "b", contactName: "B", occurredAt: 3 }),
      lend({ id: "3", contactId: "a", contactName: "A", occurredAt: 2 }),
    ];
    expect(recentLendContacts(rows)).toEqual([
      { contactName: "B", contactId: "b" },
      { contactName: "A", contactId: "a" },
    ]);
    expect(recentLendContacts(rows, 1)).toHaveLength(1);
  });

  it("flags shared ledgers, uses the newest currency and attributes the other side", () => {
    const rows = [
      lend({ id: "old", contactId: "dimo:c1", currency: "INR", occurredAt: 1 }),
      lend({
        id: "new",
        contactId: "dimo:c1",
        contactName: "Alice Smith",
        currency: "USD",
        occurredAt: 2,
        createdBy: "contact",
      }),
      lend({ id: "mine", contactId: "cn-bob", occurredAt: 3 }),
    ];
    const summaries = lendContactSummaries(rows);
    expect(summaries.find((s) => s.contactId === "dimo:c1")).toMatchObject({
      shared: true,
      currency: "USD",
    });
    expect(summaries.find((s) => s.contactId === "cn-bob")?.shared).toBe(false);
    expect(lendAttribution(rows[1])).toBe("Added by Alice");
    expect(lendAttribution({ ...rows[0], lastEditedBy: "contact" })).toBe("Edited by Ari");
    expect(lendAttribution(rows[2])).toBeNull();
  });

  it("picks a repayment kind only when it settles without overshooting", () => {
    expect(lendKindFor("got", 50, 100)).toBe("repaid");
    expect(lendKindFor("got", 100, 100)).toBe("repaid");
    expect(lendKindFor("got", 150, 100)).toBe("borrowed");
    expect(lendKindFor("got", 50, 0)).toBe("borrowed");
    expect(lendKindFor("gave", 50, -100)).toBe("returned");
    expect(lendKindFor("gave", 150, -100)).toBe("lent");
    expect(lendKindFor("gave", 50, 20)).toBe("lent");
    expect(lendFlow("repaid")).toBe("got");
    expect(lendFlow("returned")).toBe("gave");
  });

  it("lists settled people too, most recent first", () => {
    const rows = [
      lend({ id: "a", contactId: "a", contactName: "A", amount: 10, occurredAt: 1 }),
      lend({ id: "a2", contactId: "a", contactName: "A", amount: 10, kind: "repaid", occurredAt: 3 }),
      lend({ id: "b", contactId: "b", contactName: "B", amount: 5, occurredAt: 2 }),
    ];
    expect(allLendContactSummaries(rows).map((summary) => [summary.contactId, summary.balance])).toEqual([
      ["a", 0],
      ["b", 5],
    ]);
  });
});
