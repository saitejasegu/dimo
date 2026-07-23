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

  it("round-trips transaction and recurring currency metadata", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|currency-user",
    });
    await t.mutation(push, {
      workspaceId: "global",
      operations: [
        {
          ...operation,
          payload: {
            ...operation.payload,
            amountMinor: 227_611,
            currency: "INR",
            sourceCurrency: "USD",
            sourceAmountMinor: 2_360,
            exchangeRate: 96.44538771223525,
          },
        },
        {
          operationId: "op-recurring",
          workspaceId: "global",
          entityType: "recurring",
          entityId: "recurring-1",
          version: { timestamp: 101, counter: 0, deviceId: "device-a" },
          payload: {
            id: "recurring-1",
            name: "Cursor",
            amountMinor: 2_360,
            categoryId: "category-software",
            paymentMethodId: "payment-method-cash",
            frequency: "monthly",
            anchorDate: "2026-07-31",
            paused: false,
            currency: "USD",
          },
          deleted: false,
        },
      ],
    });

    const result = await t.query(pull, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(result.entities.map((entity: { payload: unknown }) => entity.payload)).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          currency: "INR",
          sourceCurrency: "USD",
          sourceAmountMinor: 2_360,
          exchangeRate: 96.44538771223525,
        }),
        expect.objectContaining({ currency: "USD", amountMinor: 2_360 }),
      ]),
    );
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
          contactId: "cn-sam",
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

  it("preserves native-owned emailMessage rows when clearing web-owned types", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|user-a",
    });
    await t.mutation(push, { workspaceId: "global", operations: [operation] });
    await t.mutation(push, {
      workspaceId: "global",
      operations: [{
        operationId: "email-1",
        workspaceId: "global",
        entityType: "emailMessage",
        entityId: "10:accountsubmsg-1",
        version: { timestamp: 100, counter: 0, deviceId: "device-a" },
        payload: {
          id: "10:accountsubmsg-1",
          accountId: "accountsub",
          accountEmail: "user@example.com",
          gmailMessageId: "msg-1",
          threadId: "thread-1",
          senderAddress: "store@example.com",
          subject: "Receipt",
          snippet: "Paid 10.00",
          internalDate: 100,
          normalizedBodyText: "Full receipt body with every line of the email.",
          classification: "purchase",
          merchant: "Store",
          amount: "10.00",
          currency: "INR",
          state: "added",
          linkedTransactionId: "tx-1",
          reviewedAt: 100,
          createdAt: 100,
          updatedAt: 100,
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
    expect(result.entities[0].entityType).toBe("emailMessage");
    expect(result.entities[0].payload).toMatchObject({
      state: "added",
      linkedTransactionId: "tx-1",
      normalizedBodyText: "Full receipt body with every line of the email.",
    });
    expect(result.latestRevision).toBe(2);
  });

  it("stores name and email on the workspace from auth and preferences", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|user-a",
      name: "Auth Name",
      email: "auth@example.com",
    });
    await t.mutation(push, { workspaceId: "global", operations: [operation] });
    const afterAuth = await t.run(async (ctx) => {
      return await ctx.db.query("workspaces").first();
    });
    expect(afterAuth?.name).toBe("Auth Name");
    expect(afterAuth?.email).toBe("auth@example.com");

    await t.mutation(push, {
      workspaceId: "global",
      operations: [{
        operationId: "prefs-1",
        workspaceId: "global",
        entityType: "preferences",
        entityId: "preferences",
        version: { timestamp: 200, counter: 0, deviceId: "device-a" },
        payload: {
          id: "preferences",
          profileName: "Profile Name",
          profileEmail: "profile@example.com",
          currency: "INR",
          weekStart: "Mon",
          theme: "light",
          navGlassOpacity: 40,
          defaultView: "home",
          defaultStatsRange: "1Y",
          notifications: { bills: true, budget: true, weekly: false, large: true },
          defaultPaymentMethodId: "payment-method-cash",
        },
        deleted: false,
      }],
    });
    const afterPrefs = await t.run(async (ctx) => {
      return await ctx.db.query("workspaces").first();
    });
    expect(afterPrefs?.name).toBe("Profile Name");
    expect(afterPrefs?.email).toBe("profile@example.com");
  });

  it("backfills workspace name and email on login for existing rows", async () => {
    const ensureWorkspaceProfile = makeFunctionReference<"mutation">(
      "sync:ensureWorkspaceProfile",
    );
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|user-a",
    });

    // Pre-create a workspace row without name/email (legacy shape).
    await t.run(async (ctx) => {
      await ctx.db.insert("workspaces", {
        ownerId: "https://api.workos.com/|user-a",
        workspaceId: "global",
        revision: 5,
      });
    });

    // WorkOS access tokens omit name/email claims; clients pass the user profile.
    const result = await t.mutation(ensureWorkspaceProfile, {
      workspaceId: "global",
      name: "Login Name",
      email: "login@example.com",
    });
    expect(result).toEqual({
      created: false,
      updated: true,
      name: "Login Name",
      email: "login@example.com",
    });

    const workspace = await t.run(async (ctx) => {
      return await ctx.db.query("workspaces").first();
    });
    expect(workspace?.revision).toBe(5);
    expect(workspace?.name).toBe("Login Name");
    expect(workspace?.email).toBe("login@example.com");
  });
});

describe("typed sync + dual-write bridge", () => {
  const pushTransactions = makeFunctionReference<"mutation">("syncTyped:pushTransactions");
  const pullTransactions = makeFunctionReference<"query">("syncTyped:pullTransactions");
  const pushCategories = makeFunctionReference<"mutation">("syncTyped:pushCategories");
  const pullCategories = makeFunctionReference<"query">("syncTyped:pullCategories");

  it("typed push is visible to blob pull and vice versa", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|bridge-user",
    });

    await t.mutation(pushTransactions, {
      workspaceId: "global",
      operations: [{
        operationId: "typed-1",
        workspaceId: "global",
        entityId: "transaction-typed",
        version: { timestamp: 100, counter: 0, deviceId: "device-a" },
        deleted: false,
        name: "Typed coffee",
        amountMinor: 500,
        occurredAt: 100,
        categoryId: "category-dining",
        paymentMethodId: "payment-method-cash",
      }],
    });

    const blobPull = await t.query(pull, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(blobPull.entities).toHaveLength(1);
    expect(blobPull.entities[0]).toMatchObject({
      entityType: "transaction",
      entityId: "transaction-typed",
      payload: { name: "Typed coffee", amountMinor: 500 },
    });

    await t.mutation(push, {
      workspaceId: "global",
      operations: [{
        ...operation,
        operationId: "blob-1",
        entityId: "transaction-blob",
        payload: { ...operation.payload, id: "transaction-blob", name: "Blob coffee" },
      }],
    });

    const typedPull = await t.query(pullTransactions, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(typedPull.entities.map((e: { entityId: string }) => e.entityId).sort()).toEqual([
      "transaction-blob",
      "transaction-typed",
    ]);
  });

  it("delete on typed protocol tombstones both stores", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|bridge-del",
    });
    await t.mutation(pushTransactions, {
      workspaceId: "global",
      operations: [{
        operationId: "create",
        workspaceId: "global",
        entityId: "transaction-1",
        version: { timestamp: 100, counter: 0, deviceId: "device-a" },
        deleted: false,
        name: "Coffee",
        amountMinor: 500,
        occurredAt: 100,
        categoryId: "c1",
        paymentMethodId: null,
      }],
    });
    await t.mutation(pushTransactions, {
      workspaceId: "global",
      operations: [{
        operationId: "delete",
        workspaceId: "global",
        entityId: "transaction-1",
        version: { timestamp: 200, counter: 0, deviceId: "device-a" },
        deleted: true,
        name: "Coffee",
        amountMinor: 500,
        occurredAt: 100,
        categoryId: "c1",
        paymentMethodId: null,
      }],
    });

    const blob = await t.query(pull, { workspaceId: "global", afterRevision: 0, limit: 100 });
    expect(blob.entities[0].deleted).toBe(true);
    const typed = await t.query(pullTransactions, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(typed.entities[0].deleted).toBe(true);
  });

  it("orders revisions across typed tables from the shared workspace counter", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|cross-table",
    });
    await t.mutation(pushCategories, {
      workspaceId: "global",
      operations: [{
        operationId: "cat",
        workspaceId: "global",
        entityId: "category-1",
        version: { timestamp: 100, counter: 0, deviceId: "a" },
        deleted: false,
        name: "Food",
        emoji: "🍽",
        monthlyBudgetMinor: null,
        tint: "neutral",
        sortOrder: 0,
        system: false,
      }],
    });
    await t.mutation(pushTransactions, {
      workspaceId: "global",
      operations: [{
        operationId: "tx",
        workspaceId: "global",
        entityId: "transaction-1",
        version: { timestamp: 101, counter: 0, deviceId: "a" },
        deleted: false,
        name: "Lunch",
        amountMinor: 1000,
        occurredAt: 100,
        categoryId: "category-1",
        paymentMethodId: null,
      }],
    });

    const cats = await t.query(pullCategories, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    const txs = await t.query(pullTransactions, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(cats.entities[0].serverRevision).toBe(1);
    expect(txs.entities[0].serverRevision).toBe(2);
    expect(cats.latestRevision).toBe(2);
    expect(txs.latestRevision).toBe(2);
  });
});
