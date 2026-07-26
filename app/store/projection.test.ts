import { describe, expect, it } from "vitest";
import { entityKey, type StoredRow } from "@/data/model";
import { projectEntities, type StoredRowEntry } from "@/store/projection";

function row(
  entityType: StoredRowEntry["entityType"],
  entityId: string,
  fields: Record<string, unknown>,
  overrides: { deleted?: boolean; timestamp?: number; counter?: number } = {},
): StoredRowEntry {
  return {
    entityType,
    row: {
      key: entityKey(entityType, entityId),
      workspaceId: "global",
      entityId,
      version: {
        timestamp: overrides.timestamp ?? 1,
        counter: overrides.counter ?? 0,
        deviceId: "device-a",
      },
      deleted: overrides.deleted ?? false,
      serverRevision: 1,
      ...fields,
    } as unknown as StoredRow,
  };
}

const CATEGORY = row("category", "cat-food", {
  name: "Food",
  emoji: "🍜",
  monthlyBudgetMinor: 500_00,
  tint: "neutral",
  sortOrder: 0,
  system: false,
});

const CASH = row("paymentMethod", "payment-method-cash", {
  name: "Cash",
  type: "Cash",
  detail: "",
  archived: false,
});

const TRANSACTION = row("transaction", "tx-1", {
  name: "Ramen",
  amountMinor: 240_00,
  occurredAt: Date.UTC(2026, 5, 1, 6, 30),
  categoryId: "cat-food",
  paymentMethodId: "payment-method-cash",
  currency: "INR",
});

const BASE_ROWS = [CATEGORY, CASH, TRANSACTION];

const OPTIONS = { rates: null, lastPaymentMethodId: null, previous: null };

describe("projectEntities", () => {
  it("projects category and payment-method labels onto transactions", () => {
    const snapshot = projectEntities(BASE_ROWS, OPTIONS);
    expect(snapshot).not.toBeNull();
    expect(snapshot!.transactions).toHaveLength(1);
    expect(snapshot!.transactions[0]).toMatchObject({
      name: "Ramen",
      category: "Food",
      emoji: "🍜",
      paymentMethod: "Cash",
      amount: 240,
    });
    expect(snapshot!.limits).toEqual({ Food: 500 });
  });

  it("returns null when nothing observable changed", () => {
    const first = projectEntities(BASE_ROWS, OPTIONS);
    const second = projectEntities(BASE_ROWS, { ...OPTIONS, previous: first });
    expect(second).toBeNull();
  });

  it("reuses the transaction projection when only an unrelated type changed", () => {
    const first = projectEntities(BASE_ROWS, OPTIONS)!;
    const withLend = [
      ...BASE_ROWS,
      row("lend", "lend-1", {
        contactName: "Sam",
        contactId: "sam",
        amountMinor: 100_00,
        occurredAt: Date.UTC(2026, 5, 2),
        comment: "",
        kind: "lent",
      }),
    ];
    const second = projectEntities(withLend, { ...OPTIONS, previous: first })!;
    expect(second).not.toBeNull();
    expect(second.lends).toHaveLength(1);
    // Same array instance: the transaction slice was not remapped.
    expect(second.transactions).toBe(first.transactions);
  });

  it("remaps transactions when a category is renamed", () => {
    const first = projectEntities(BASE_ROWS, OPTIONS)!;
    const renamed = [
      row(
        "category",
        "cat-food",
        {
          name: "Groceries",
          emoji: "🥕",
          monthlyBudgetMinor: 500_00,
          tint: "neutral",
          sortOrder: 0,
          system: false,
        },
        { timestamp: 2 },
      ),
      CASH,
      TRANSACTION,
    ];
    const second = projectEntities(renamed, { ...OPTIONS, previous: first })!;
    expect(second.transactions[0].category).toBe("Groceries");
    expect(second.transactions[0].emoji).toBe("🥕");
  });

  it("excludes tombstoned rows", () => {
    const rows = [
      CATEGORY,
      CASH,
      row(
        "transaction",
        "tx-1",
        {
          name: "Ramen",
          amountMinor: 240_00,
          occurredAt: Date.UTC(2026, 5, 1),
          categoryId: "cat-food",
          paymentMethodId: "payment-method-cash",
          currency: "INR",
        },
        { deleted: true, timestamp: 3 },
      ),
    ];
    const snapshot = projectEntities(rows, OPTIONS)!;
    expect(snapshot.transactions).toHaveLength(0);
  });

  it("ignores email rows, which have their own local store", () => {
    const first = projectEntities(BASE_ROWS, OPTIONS)!;
    const withEmail = [
      ...BASE_ROWS,
      row("emailMessage", "email-1", {
        accountId: "acct",
        accountEmail: "a@b.c",
        gmailMessageId: "g1",
        threadId: "t1",
        senderAddress: "s@b.c",
        subject: "Receipt",
        snippet: "",
        internalDate: 1,
        state: "pendingPurchase",
        createdAt: 1,
        updatedAt: 1,
      }),
    ];
    expect(projectEntities(withEmail, { ...OPTIONS, previous: first })).toBeNull();
  });

  it("resolves the last-used payment method label", () => {
    const snapshot = projectEntities(BASE_ROWS, {
      ...OPTIONS,
      lastPaymentMethodId: "payment-method-cash",
    })!;
    expect(snapshot.lastPaymentMethod).toBe("Cash");
  });
});
