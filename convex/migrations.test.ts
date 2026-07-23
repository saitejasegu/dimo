import { describe, expect, it } from "vitest";
import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import schema from "./schema";
import { explodePayloadForTest } from "./migrations";
import { payloadFromTyped, writeTyped } from "./compat";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
const pushTransactions = makeFunctionReference<"mutation">("syncTyped:pushTransactions");
const pullTransactions = makeFunctionReference<"query">("syncTyped:pullTransactions");

describe("typed storage helpers", () => {
  it("explodes payload id into entityId fields", () => {
    expect(
      explodePayloadForTest({
        id: "transaction-1",
        name: "Coffee",
        amountMinor: 100,
        occurredAt: 1,
        categoryId: "c1",
        paymentMethodId: null,
      }),
    ).toEqual({
      name: "Coffee",
      amountMinor: 100,
      occurredAt: 1,
      categoryId: "c1",
      paymentMethodId: null,
    });
  });

  it("round-trips typed ↔ blob payload shape", () => {
    const typed = {
      ownerId: "owner",
      workspaceId: "global",
      entityId: "transaction-1",
      version: { timestamp: 1, counter: 0, deviceId: "d" },
      deleted: false,
      revision: 1,
      name: "Coffee",
      amountMinor: 500,
      occurredAt: 100,
      categoryId: "c1",
      paymentMethodId: null as string | null,
    };
    const payload = payloadFromTyped("transaction", typed);
    expect(payload).toMatchObject({ id: "transaction-1", name: "Coffee", amountMinor: 500 });
  });

  it("writes a typed row that typed pull can read", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|backfill",
    });
    await t.run(async (ctx) => {
      await writeTyped(ctx, "transaction", {
        ownerId: "https://api.workos.com/|backfill",
        workspaceId: "global",
        entityId: "legacy-tx",
        version: { timestamp: 50, counter: 0, deviceId: "old" },
        deleted: false,
        revision: 3,
        name: "Legacy",
        amountMinor: 250,
        occurredAt: 50,
        categoryId: "c1",
        paymentMethodId: null,
      });
      await ctx.db.insert("workspaces", {
        ownerId: "https://api.workos.com/|backfill",
        workspaceId: "global",
        revision: 3,
      });
    });

    const page = await t.query(pullTransactions, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(page.entities).toHaveLength(1);
    expect(page.entities[0]).toMatchObject({
      entityId: "legacy-tx",
      name: "Legacy",
      amountMinor: 250,
      serverRevision: 3,
    });
  });

  it("typed push lands for typed pull", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|backfill2",
    });
    await t.mutation(pushTransactions, {
      workspaceId: "global",
      operations: [
        {
          operationId: "op-1",
          workspaceId: "global",
          entityId: "tx-1",
          version: { timestamp: 1, counter: 0, deviceId: "d" },
          deleted: false,
          name: "Tea",
          amountMinor: 100,
          occurredAt: 1,
          categoryId: "c1",
          paymentMethodId: null,
        },
      ],
    });
    const typed = await t.query(pullTransactions, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 10,
    });
    expect(typed.entities[0].name).toBe("Tea");
  });
});
