import { describe, expect, it } from "vitest";
import type { Lend } from "@/lib/types";
import {
  groupLendsByDay,
  lendContactSummaries,
  lendingTotals,
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

    expect(lendingTotals(rows)).toEqual({ outstanding: 300, lent: 550, repaid: 250 });
    expect(lendContactSummaries(rows)).toMatchObject([
      { contactName: "Ari", outstanding: 300, entryCount: 2 },
    ]);
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
