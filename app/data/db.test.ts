import "fake-indexeddb/auto";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import {
  activateUserDatabase,
  db,
  deleteAllLocalDatabases,
} from "@/data/db";
import { initializeLocalDatabase } from "@/data/repository";

describe("local database lifecycle", () => {
  beforeEach(async () => {
    db.close();
    await db.delete();
  });
  afterAll(() => db.close());

  it("deletes every dimo-expenses IndexedDB database on wipe", async () => {
    activateUserDatabase("user-a");
    await initializeLocalDatabase();
    expect(await db.paymentMethods.count()).toBeGreaterThan(0);

    activateUserDatabase("user-b");
    await initializeLocalDatabase();
    expect(await db.paymentMethods.count()).toBeGreaterThan(0);

    await deleteAllLocalDatabases();

    const names = (await indexedDB.databases())
      .map((entry) => entry.name)
      .filter((name): name is string => !!name && name.startsWith("dimo-expenses"));
    expect(names).toEqual([]);
  });
});
