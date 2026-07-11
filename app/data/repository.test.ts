import "fake-indexeddb/auto";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { db } from "@/data/db";
import { DEFAULT_PREFERENCES, entityKey } from "@/data/model";
import {
  initializeLocalDatabase,
  saveEntity,
  enqueueFullUpload,
  sanitizePayload,
} from "@/data/repository";

describe("local repository", () => {
  beforeEach(async () => {
    db.close();
    await db.delete();
  });
  afterAll(() => db.close());

  it("bootstraps deterministic defaults exactly once", async () => {
    await initializeLocalDatabase();
    expect(await db.entities.count()).toBe(7);
    expect(await db.outbox.count()).toBe(7);
    expect(await db.entities.get(entityKey("paymentMethod", "payment-method-cash"))).toBeTruthy();
    await initializeLocalDatabase();
    expect(await db.entities.count()).toBe(7);
    expect(await db.outbox.count()).toBe(7);
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

  it("atomically replaces the outbox operation for a newer entity edit", async () => {
    await initializeLocalDatabase();
    const payload = { id: "category-test", name: "Test", emoji: "🧪", monthlyBudgetMinor: null, tint: "neutral" as const, sortOrder: 10, system: false };
    await saveEntity("category", payload);
    const first = await db.outbox.get(entityKey("category", payload.id));
    await saveEntity("category", { ...payload, name: "Updated" });
    const second = await db.outbox.get(entityKey("category", payload.id));
    expect(second?.operationId).not.toBe(first?.operationId);
    expect((second?.payload as typeof payload).name).toBe("Updated");
    expect(await db.entities.count()).toBe(8);
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
