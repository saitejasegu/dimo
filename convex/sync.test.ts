/// <reference types="vite/client" />
import { describe, expect, it } from "vitest";
import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import schema from "./schema";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
const push = makeFunctionReference<"mutation">("sync:push");
const pull = makeFunctionReference<"query">("sync:pull");
const currentRevision = makeFunctionReference<"query">("sync:currentRevision");
const clearWorkspace = makeFunctionReference<"mutation">("sync:clearWorkspace");

const operation = {
  operationId: "op-1",
  workspaceId: "global",
  entityType: "transaction" as const,
  entityId: "transaction-1",
  version: { timestamp: 100, counter: 0, deviceId: "device-a" },
  payload: {
    id: "transaction-1",
    name: "Coffee",
    amountMinor: 12_300,
    occurredAt: 100,
    categoryId: "category-dining",
    paymentMethodId: "payment-method-cash",
  },
  deleted: false,
};

describe("Convex sync protocol", () => {
  it("rejects every sync endpoint without authentication", async () => {
    const t = convexTest(schema, modules);
    await expect(
      t.mutation(push, { workspaceId: "global", operations: [operation] }),
    ).rejects.toThrow("Not authenticated");
    await expect(
      t.query(pull, { workspaceId: "global", afterRevision: 0, limit: 100 }),
    ).rejects.toThrow("Not authenticated");
    await expect(
      t.query(currentRevision, { workspaceId: "global" }),
    ).rejects.toThrow("Not authenticated");
    await expect(
      t.mutation(clearWorkspace, { workspaceId: "global", entityTypes: ["transaction"] }),
    ).rejects.toThrow("Not authenticated");
  });

  it("is idempotent and exposes accepted records by revision", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|user-a",
    });
    const first = await t.mutation(push, { workspaceId: "global", operations: [operation] });
    const duplicate = await t.mutation(push, { workspaceId: "global", operations: [operation] });
    expect(first.acknowledgements[0].applied).toBe(true);
    expect(duplicate.acknowledgements[0].applied).toBe(false);
    const result = await t.query(pull, { workspaceId: "global", afterRevision: 0, limit: 100 });
    expect(result.entities).toHaveLength(1);
    expect(result.entities[0].payload.name).toBe("Coffee");
    expect(result.latestRevision).toBe(1);
  });

  it("keeps a newer tombstone over a stale update", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|user-a",
    });
    await t.mutation(push, { workspaceId: "global", operations: [operation] });
    await t.mutation(push, {
      workspaceId: "global",
      operations: [{ ...operation, operationId: "delete", deleted: true, version: { ...operation.version, timestamp: 200 } }],
    });
    const stale = await t.mutation(push, {
      workspaceId: "global",
      operations: [{ ...operation, operationId: "stale", payload: { ...operation.payload, name: "Stale" } }],
    });
    expect(stale.acknowledgements[0].applied).toBe(false);
    const result = await t.query(pull, { workspaceId: "global", afterRevision: 0, limit: 100 });
    expect(result.entities[0].deleted).toBe(true);
  });

  it("isolates the same entity and revision stream between users", async () => {
    const base = convexTest(schema, modules);
    const alice = base.withIdentity({ tokenIdentifier: "https://api.workos.com/|alice" });
    const bob = base.withIdentity({ tokenIdentifier: "https://api.workos.com/|bob" });

    await alice.mutation(push, { workspaceId: "global", operations: [operation] });
    const bobBefore = await bob.query(pull, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(bobBefore.entities).toEqual([]);
    expect(bobBefore.latestRevision).toBe(0);

    await bob.mutation(push, {
      workspaceId: "global",
      operations: [{
        ...operation,
        operationId: "bob-op",
        payload: { ...operation.payload, name: "Bob's coffee" },
      }],
    });
    const aliceResult = await alice.query(pull, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    const bobResult = await bob.query(pull, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(aliceResult.entities[0].payload.name).toBe("Coffee");
    expect(bobResult.entities[0].payload.name).toBe("Bob's coffee");
    expect(aliceResult.latestRevision).toBe(1);
    expect(bobResult.latestRevision).toBe(1);
  });

  it("clears only the authenticated owner's workspace for a full re-upload", async () => {
    const base = convexTest(schema, modules);
    const alice = base.withIdentity({ tokenIdentifier: "https://api.workos.com/|alice" });
    const bob = base.withIdentity({ tokenIdentifier: "https://api.workos.com/|bob" });

    await alice.mutation(push, { workspaceId: "global", operations: [operation] });
    await bob.mutation(push, {
      workspaceId: "global",
      operations: [{
        ...operation,
        operationId: "bob-op",
        payload: { ...operation.payload, name: "Bob's coffee" },
      }],
    });

    const cleared = await alice.mutation(clearWorkspace, {
      workspaceId: "global",
      entityTypes: ["transaction"],
    });
    expect(cleared.deleted).toBe(1);
    expect(cleared.hasMore).toBe(false);

    const aliceAfter = await alice.query(pull, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(aliceAfter.entities).toEqual([]);
    expect(aliceAfter.latestRevision).toBe(0);

    const bobAfter = await bob.query(pull, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(bobAfter.entities).toHaveLength(1);
    expect(bobAfter.latestRevision).toBe(1);
  });

  it("clears only the requested entity types and preserves others", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|user-a",
    });
    await t.mutation(push, { workspaceId: "global", operations: [operation] });
    await t.mutation(push, {
      workspaceId: "global",
      operations: [{
        operationId: "lend-1",
        workspaceId: "global",
        entityType: "lend",
        entityId: "lend-1",
        version: { timestamp: 100, counter: 0, deviceId: "device-a" },
        payload: {
          id: "lend-1",
          contactName: "Sam",
          amountMinor: 5000,
          occurredAt: 100,
          comment: "",
          kind: "lent",
        },
        deleted: false,
      }],
    });

    const cleared = await t.mutation(clearWorkspace, {
      workspaceId: "global",
      entityTypes: ["transaction", "category", "paymentMethod", "recurring", "preferences"],
    });
    expect(cleared.deleted).toBe(1);
    expect(cleared.hasMore).toBe(false);

    const result = await t.query(pull, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(result.entities).toHaveLength(1);
    expect(result.entities[0].entityType).toBe("lend");
    expect(result.latestRevision).toBe(2);
  });
});
