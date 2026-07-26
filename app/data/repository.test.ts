import "fake-indexeddb/auto";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { db } from "@/data/db";
import {
  DEFAULT_PREFERENCES,
  TOMBSTONE_RETENTION_DAYS,
  entityKey,
  type EmailMessageEntity,
} from "@/data/model";
import {
  backfillMissingPaymentMethodIds,
  backfillRecurringCurrencies,
  getStoredRow,
  initializeLocalDatabase,
  mergeRemotePage,
  removeEntities,
  runPendingBackfills,
  saveEntities,
  saveEntity,
  enqueueFullUpload,
  enqueueUnsyncedDefaults,
  purgeExpiredTombstones,
  sanitizePayload,
  tableForType,
  tombstoneSweepDue,
} from "@/data/repository";

async function totalEntityCount() {
  let total = 0;
  for (const type of [
    "category",
    "paymentMethod",
    "transaction",
    "recurring",
    "lend",
    "emailMessage",
    "preferences",
  ] as const) {
    total += await tableForType(type).count();
  }
  return total;
}

describe("local repository", () => {
  beforeEach(async () => {
    db.close();
    await db.delete();
  });
  afterAll(() => db.close());

  it("bootstraps cash and preferences exactly once without seed categories", async () => {
    await initializeLocalDatabase();
    expect(await totalEntityCount()).toBe(2);
    expect(await db.outbox.count()).toBe(0);
    expect(await getStoredRow("paymentMethod", "payment-method-cash")).toBeTruthy();
    expect(await getStoredRow("preferences", "preferences")).toBeTruthy();
    await initializeLocalDatabase();
    expect(await totalEntityCount()).toBe(2);
    expect(await db.outbox.count()).toBe(0);
  });

  it("replays the cloud snapshot once for clients with stale lending payloads", async () => {
    await initializeLocalDatabase();
    await db.syncMeta.update("global", { lastPulledRevision: 42 });
    await db.deviceMeta.update("device", { bootstrapVersion: 3 });

    await initializeLocalDatabase();
    expect((await db.syncMeta.get("global"))?.lastPulledRevision).toBe(0);

    await db.syncMeta.update("global", { lastPulledRevision: 7 });
    await initializeLocalDatabase();
    expect((await db.syncMeta.get("global"))?.lastPulledRevision).toBe(7);
  });

  it("normalizes older preferences to the one-year stats default", () => {
    const olderPreferences: Partial<typeof DEFAULT_PREFERENCES> = {
      ...DEFAULT_PREFERENCES,
    };
    delete olderPreferences.defaultStatsRange;
    expect(
      sanitizePayload("preferences", olderPreferences as typeof DEFAULT_PREFERENCES)
        .defaultStatsRange,
    ).toBe("1Y");
  });

  it("preserves and normalizes native email purchase group ids", () => {
    const message: EmailMessageEntity = {
      id: "message-1",
      accountId: "account-1",
      accountEmail: "person@example.com",
      gmailMessageId: "gmail-1",
      threadId: "thread-1",
      senderAddress: "store@example.com",
      subject: "Receipt",
      snippet: "Paid 10.00",
      internalDate: 100,
      state: "pendingPurchase",
      purchaseGroupId: "  email-purchase-group-1  ",
      createdAt: 100,
      updatedAt: 100,
    };
    expect(sanitizePayload("emailMessage", message).purchaseGroupId).toBe(
      "email-purchase-group-1",
    );
    expect(
      sanitizePayload("emailMessage", { ...message, purchaseGroupId: " " })
        .purchaseGroupId,
    ).toBeNull();
  });

  it("enqueues bootstrap defaults only when they were never pulled from the server", async () => {
    await initializeLocalDatabase();
    expect(await db.outbox.count()).toBe(0);
    await enqueueUnsyncedDefaults();
    expect(await db.outbox.count()).toBe(2);

    const cash = await getStoredRow("paymentMethod", "payment-method-cash");
    expect(cash).toBeTruthy();
    await db.paymentMethods.put({ ...cash!, serverRevision: 10 });
    await db.outbox.clear();
    await enqueueUnsyncedDefaults();
    const pending = await db.outbox.toArray();
    expect(pending.some((op) => op.entityId === "payment-method-cash")).toBe(false);
    expect(pending).toHaveLength(1);
  });

  it("atomically replaces the outbox operation for a newer entity edit", async () => {
    await initializeLocalDatabase();
    const payload = { id: "category-test", name: "Test", emoji: "🧪", monthlyBudgetMinor: null, tint: "neutral" as const, sortOrder: 10, system: false };
    await saveEntity("category", payload);
    const first = await db.outbox.get(entityKey("category", payload.id));
    await saveEntity("category", { ...payload, name: "Updated" });
    const second = await db.outbox.get(entityKey("category", payload.id));
    expect(second?.operationId).not.toBe(first?.operationId);
    const stored = await getStoredRow("category", payload.id);
    expect(stored?.name).toBe("Updated");
    expect(await totalEntityCount()).toBe(3);
  });

  it("enqueues every local entity for a full cloud re-upload", async () => {
    await initializeLocalDatabase();
    await db.outbox.clear();
    expect(await db.outbox.count()).toBe(0);
    await enqueueFullUpload();
    expect(await db.outbox.count()).toBe(await totalEntityCount());
    const blocked = await db.outbox.where("status").equals("blocked").count();
    expect(blocked).toBe(0);
  });

  it("backfills a legacy recurring row with the synced account currency", async () => {
    await initializeLocalDatabase();
    await saveEntity("preferences", { ...DEFAULT_PREFERENCES, currency: "USD" });
    await saveEntity("recurring", {
      id: "legacy-recurring",
      name: "Cursor",
      amountMinor: 2360,
      categoryId: "category-software",
      paymentMethodId: "payment-method-cash",
      frequency: "monthly",
      anchorDate: "2026-07-31",
      paused: false,
    });
    await saveEntity("transaction", {
      id: "legacy-tx",
      name: "Coffee",
      amountMinor: 500,
      occurredAt: 1_700_000_000_000,
      categoryId: "category-software",
      paymentMethodId: "payment-method-cash",
    });
    await db.outbox.clear();

    expect(await backfillRecurringCurrencies()).toBe(2);
    const recurring = await getStoredRow("recurring", "legacy-recurring");
    const transaction = await getStoredRow("transaction", "legacy-tx");
    expect(recurring).toMatchObject({ currency: "USD" });
    expect(transaction).toMatchObject({ currency: "USD" });
    expect(await backfillRecurringCurrencies()).toBe(0);
  });

  it("backfills missing payment method ids onto the account default", async () => {
    await initializeLocalDatabase();
    await saveEntity("preferences", {
      ...DEFAULT_PREFERENCES,
      defaultPaymentMethodId: "payment-method-cash",
    });
    await saveEntity("transaction", {
      id: "legacy-null-pm",
      name: "Legacy",
      amountMinor: 100,
      occurredAt: 1,
      categoryId: "c1",
      paymentMethodId: "payment-method-cash",
    });
    const existing = await getStoredRow("transaction", "legacy-null-pm");
    expect(existing).toBeTruthy();
    await tableForType("transaction").put({
      ...existing!,
      paymentMethodId: null,
    } as never);
    await db.outbox.clear();

    expect(await backfillMissingPaymentMethodIds()).toBe(1);
    const row = await getStoredRow("transaction", "legacy-null-pm");
    expect(row).toMatchObject({ paymentMethodId: "payment-method-cash" });
    expect(await backfillMissingPaymentMethodIds()).toBe(0);
  });

  it("does not rewrite rows already set to the fallback when payment methods are missing", async () => {
    await initializeLocalDatabase();
    await saveEntity("transaction", {
      id: "orphan-pm",
      name: "Orphan",
      amountMinor: 100,
      occurredAt: 1,
      categoryId: "c1",
      paymentMethodId: "payment-method-cash",
    });
    // Simulate a transient empty payment-method table after pull/clear races.
    await tableForType("paymentMethod").clear();
    await db.outbox.clear();

    expect(await backfillMissingPaymentMethodIds()).toBe(0);
  });
});

describe("sanitizePayload foreign-currency fields", () => {
  it("preserves transaction currency and source-currency fields when present", () => {
    const clean = sanitizePayload("transaction", {
      id: "t1",
      name: "Hotel",
      amountMinor: 81_818,
      occurredAt: 1_700_000_000_000,
      categoryId: "c1",
      paymentMethodId: null as unknown as string,
      currency: "INR",
      sourceCurrency: "USD",
      sourceAmountMinor: 1000,
      exchangeRate: 81.818,
    });
    expect(clean).toMatchObject({
      amountMinor: 81_818,
      paymentMethodId: "payment-method-cash",
      currency: "INR",
      sourceCurrency: "USD",
      sourceAmountMinor: 1000,
      exchangeRate: 81.818,
    });
  });

  it("omits source fields for a plain default-currency transaction but keeps currency", () => {
    const clean = sanitizePayload("transaction", {
      id: "t2",
      name: "Chai",
      amountMinor: 5000,
      occurredAt: 1_700_000_000_000,
      categoryId: "c1",
      paymentMethodId: null as unknown as string,
      currency: "INR",
    });
    expect(clean).toMatchObject({
      currency: "INR",
      paymentMethodId: "payment-method-cash",
    });
    expect(clean).not.toHaveProperty("sourceCurrency");
    expect(clean).not.toHaveProperty("sourceAmountMinor");
    expect(clean).not.toHaveProperty("exchangeRate");
  });

  it("preserves recurring currency and drops it when absent", () => {
    const foreign = sanitizePayload("recurring", {
      id: "r1",
      name: "Netflix",
      amountMinor: 1500,
      categoryId: "c1",
      paymentMethodId: null as unknown as string,
      frequency: "monthly",
      anchorDate: "2026-01-10",
      paused: false,
      currency: "USD",
    });
    expect(foreign).toMatchObject({
      currency: "USD",
      paymentMethodId: "payment-method-cash",
    });

    const local = sanitizePayload("recurring", {
      id: "r2",
      name: "Rent",
      amountMinor: 50_000,
      categoryId: "c1",
      paymentMethodId: null as unknown as string,
      frequency: "monthly",
      anchorDate: "2026-01-10",
      paused: false,
    });
    expect(local).not.toHaveProperty("currency");
    expect(local).toMatchObject({ paymentMethodId: "payment-method-cash" });
  });
});

describe("tombstone retention", () => {
  beforeEach(async () => {
    db.close();
    await db.delete();
  });
  afterAll(() => db.close());

  it("hard-deletes expired local tombstones but keeps fresh ones and pending deletes", async () => {
    await initializeLocalDatabase();
    const now = Date.UTC(2026, 6, 22);
    const msPerDay = 24 * 60 * 60 * 1000;
    const payload = {
      id: "transaction-expired",
      name: "Old",
      amountMinor: 100,
      occurredAt: 1,
      categoryId: "c1",
      paymentMethodId: "payment-method-cash",
    };

    await saveEntity("transaction", payload);
    const key = entityKey("transaction", payload.id);
    await db.outbox.delete(key);
    await db.transactions.update(key, {
      deleted: true,
      version: {
        timestamp: now - (TOMBSTONE_RETENTION_DAYS + 2) * msPerDay,
        counter: 0,
        deviceId: "test",
      },
    });

    const freshKey = entityKey("transaction", "transaction-fresh");
    await db.transactions.put({
      key: freshKey,
      workspaceId: "global",
      entityId: "transaction-fresh",
      version: {
        timestamp: now - 5 * msPerDay,
        counter: 0,
        deviceId: "test",
      },
      name: "Fresh",
      amountMinor: 100,
      occurredAt: 1,
      categoryId: "c1",
      paymentMethodId: "payment-method-cash",
      deleted: true,
      serverRevision: 1,
    });

    const pendingKey = entityKey("transaction", "transaction-pending");
    await saveEntity("transaction", { ...payload, id: "transaction-pending", name: "Pending" });
    await db.transactions.update(pendingKey, {
      deleted: true,
      version: {
        timestamp: now - (TOMBSTONE_RETENTION_DAYS + 2) * msPerDay,
        counter: 0,
        deviceId: "test",
      },
    });

    expect(await purgeExpiredTombstones(now)).toBe(1);
    expect(await db.transactions.get(key)).toBeUndefined();
    expect(await db.transactions.get(freshKey)).toBeTruthy();
    expect(await db.transactions.get(pendingKey)).toBeTruthy();
  });

  it("tombstones many rows in one pass with strictly increasing versions", async () => {
    await initializeLocalDatabase();
    const ids = ["tx-a", "tx-b", "tx-c"];
    await saveEntities(
      ids.map((id) => ({
        entityType: "transaction" as const,
        payload: {
          id,
          name: id,
          amountMinor: 100,
          occurredAt: Date.now(),
          categoryId: "category-food",
          paymentMethodId: "payment-method-cash",
          currency: "INR",
        },
      })),
    );

    await removeEntities("transaction", [...ids, "tx-missing", "tx-a"]);

    const rows = await Promise.all(ids.map((id) => getStoredRow("transaction", id)));
    expect(rows.every((row) => row?.deleted)).toBe(true);
    // Each delete carries its own version, so last-write-wins stays well defined.
    const versions = rows.map((row) => `${row!.version.timestamp}:${row!.version.counter}`);
    expect(new Set(versions).size).toBe(ids.length);
    // One queued operation per row, replacing the create.
    expect(await db.outbox.count()).toBe(ids.length);
  });

  it("issues consecutive versions for a batch save from one clock reservation", async () => {
    await initializeLocalDatabase();
    const before = await db.deviceMeta.get("device");
    await saveEntities(
      ["a", "b", "c", "d"].map((id) => ({
        entityType: "transaction" as const,
        payload: {
          id: `tx-${id}`,
          name: id,
          amountMinor: 100,
          occurredAt: Date.now(),
          categoryId: "category-food",
          paymentMethodId: "payment-method-cash",
          currency: "INR",
        },
      })),
    );
    const rows = await Promise.all(
      ["a", "b", "c", "d"].map((id) => getStoredRow("transaction", `tx-${id}`)),
    );
    const counters = rows.map((row) => row!.version.counter);
    expect(counters).toEqual([...counters].sort((x, y) => x - y));
    expect(new Set(counters).size).toBe(4);
    const after = await db.deviceMeta.get("device");
    // The reserved range is committed, so a later write cannot reuse these counters.
    expect(after!.clockCounter).toBeGreaterThanOrEqual(Math.max(...counters));
    expect(after!.clockTimestamp).toBeGreaterThanOrEqual(before!.clockTimestamp);
  });

  it("runs the legacy repairs once, then re-arms them when a pull delivers rows", async () => {
    await initializeLocalDatabase();
    const legacy = {
      id: "recurring-legacy",
      name: "Legacy",
      amountMinor: 100_00,
      categoryId: "category-bills",
      paymentMethodId: "payment-method-cash",
      frequency: "monthly" as const,
      anchorDate: "2026-01-01",
      paused: false,
    };
    await saveEntity("recurring", legacy);
    await db.recurring.update(entityKey("recurring", legacy.id), { currency: undefined });

    const first = await runPendingBackfills();
    expect(first.currencies).toBe(1);
    // Already applied: no scan, no further repairs.
    await db.recurring.update(entityKey("recurring", legacy.id), { currency: undefined });
    expect(await runPendingBackfills()).toEqual({ currencies: 0, paymentMethods: 0 });

    // A pulled transaction re-arms the repairs so legacy remote data is normalized.
    await mergeRemotePage(
      "transaction",
      [
        {
          key: entityKey("transaction", "tx-remote"),
          workspaceId: "global",
          entityId: "tx-remote",
          version: { timestamp: Date.now(), counter: 0, deviceId: "remote" },
          deleted: false,
          serverRevision: 9,
          name: "Remote",
          amountMinor: 100,
          occurredAt: Date.now(),
          categoryId: "category-food",
          paymentMethodId: "payment-method-cash",
          currency: "INR",
        } as never,
      ],
      9,
    );
    expect((await runPendingBackfills()).currencies).toBe(1);
  });

  it("throttles the tombstone retention sweep", async () => {
    await initializeLocalDatabase();
    const now = Date.now();
    await purgeExpiredTombstones(now);
    expect(tombstoneSweepDue(now)).toBe(false);
    expect(tombstoneSweepDue(now + 7 * 60 * 60 * 1000)).toBe(true);
  });
});
