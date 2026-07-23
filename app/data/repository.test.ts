import "fake-indexeddb/auto";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { db } from "@/data/db";
import { DEFAULT_PREFERENCES, TOMBSTONE_RETENTION_DAYS, entityKey } from "@/data/model";
import {
  backfillRecurringCurrencies,
  getStoredRow,
  initializeLocalDatabase,
  saveEntity,
  enqueueFullUpload,
  enqueueUnsyncedDefaults,
  purgeExpiredTombstones,
  sanitizePayload,
  tableForType,
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
});

describe("sanitizePayload foreign-currency fields", () => {
  it("preserves transaction currency and source-currency fields when present", () => {
    const clean = sanitizePayload("transaction", {
      id: "t1",
      name: "Hotel",
      amountMinor: 81_818,
      occurredAt: 1_700_000_000_000,
      categoryId: "c1",
      paymentMethodId: null,
      currency: "INR",
      sourceCurrency: "USD",
      sourceAmountMinor: 1000,
      exchangeRate: 81.818,
    });
    expect(clean).toMatchObject({
      amountMinor: 81_818,
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
      paymentMethodId: null,
      currency: "INR",
    });
    expect(clean).toMatchObject({ currency: "INR" });
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
      paymentMethodId: null,
      frequency: "monthly",
      anchorDate: "2026-01-10",
      paused: false,
      currency: "USD",
    });
    expect(foreign).toMatchObject({ currency: "USD" });

    const local = sanitizePayload("recurring", {
      id: "r2",
      name: "Rent",
      amountMinor: 50_000,
      categoryId: "c1",
      paymentMethodId: null,
      frequency: "monthly",
      anchorDate: "2026-01-10",
      paused: false,
    });
    expect(local).not.toHaveProperty("currency");
  });

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
});
