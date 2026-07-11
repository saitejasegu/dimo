import "fake-indexeddb/auto";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { db } from "@/data/db";
import { entityKey } from "@/data/model";
import { initializeLocalDatabase, saveEntity } from "@/data/repository";

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
});
