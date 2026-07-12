import "fake-indexeddb/auto";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { db } from "@/data/db";
import { DEFAULT_PREFERENCES, entityKey } from "@/data/model";
import {
  initializeLocalDatabase,
  saveEntity,
  enqueueFullUpload,
  enqueueUnsyncedDefaults,
  sanitizePayload,
} from "@/data/repository";

describe("local repository", () => {
  beforeEach(async () => {
    db.close();
    await db.delete();
  });
  afterAll(() => db.close());

  it("bootstraps cash and preferences exactly once without seed categories", async () => {
    await initializeLocalDatabase();
    expect(await db.entities.count()).toBe(2);
    expect(await db.outbox.count()).toBe(0);
    expect(await db.entities.get(entityKey("paymentMethod", "payment-method-cash"))).toBeTruthy();
    expect(await db.entities.get(entityKey("preferences", "preferences"))).toBeTruthy();
    await initializeLocalDatabase();
    expect(await db.entities.count()).toBe(2);
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

    const cash = await db.entities.get(entityKey("paymentMethod", "payment-method-cash"));
    expect(cash).toBeTruthy();
    await db.entities.put({ ...cash!, serverRevision: 10 });
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
    expect((second?.payload as typeof payload).name).toBe("Updated");
    expect(await db.entities.count()).toBe(3);
  });

  it("enqueues every local entity for a full cloud re-upload", async () => {
    await initializeLocalDatabase();
    await db.outbox.clear();
    expect(await db.outbox.count()).toBe(0);
    await enqueueFullUpload();
    expect(await db.outbox.count()).toBe(await db.entities.count());
    const blocked = await db.outbox.where("status").equals("blocked").count();
    expect(blocked).toBe(0);
  });
});
