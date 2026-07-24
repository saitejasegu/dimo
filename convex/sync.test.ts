/// <reference types="vite/client" />
import { describe, expect, it } from "vitest";
import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import schema from "./schema";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
const pushTransactions = makeFunctionReference<"mutation">("syncTyped:pushTransactions");
const pullTransactions = makeFunctionReference<"query">("syncTyped:pullTransactions");
const pushRecurring = makeFunctionReference<"mutation">("syncTyped:pushRecurring");
const pullRecurring = makeFunctionReference<"query">("syncTyped:pullRecurring");
const pushLends = makeFunctionReference<"mutation">("syncTyped:pushLends");
const pullLends = makeFunctionReference<"query">("syncTyped:pullLends");
const pushEmailMessages = makeFunctionReference<"mutation">("syncTyped:pushEmailMessages");
const pullEmailMessages = makeFunctionReference<"query">("syncTyped:pullEmailMessages");
const pushPreferences = makeFunctionReference<"mutation">("syncTyped:pushPreferences");
const pushCategories = makeFunctionReference<"mutation">("syncTyped:pushCategories");
const pullCategories = makeFunctionReference<"query">("syncTyped:pullCategories");
const currentRevision = makeFunctionReference<"query">("syncTyped:currentRevision");
const clearWorkspace = makeFunctionReference<"mutation">("syncTyped:clearWorkspace");
const ensureWorkspaceProfile = makeFunctionReference<"mutation">(
  "syncTyped:ensureWorkspaceProfile",
);

const txOp = {
  operationId: "op-1",
  workspaceId: "global",
  entityId: "transaction-1",
  version: { timestamp: 100, counter: 0, deviceId: "device-a" },
  deleted: false,
  name: "Coffee",
  amountMinor: 12_300,
  occurredAt: 100,
  categoryId: "category-dining",
  paymentMethodId: "payment-method-cash",
};

describe("Convex typed sync protocol", () => {
  it("rejects every sync endpoint without authentication", async () => {
    const t = convexTest(schema, modules);
    await expect(
      t.mutation(pushTransactions, { workspaceId: "global", operations: [txOp] }),
    ).rejects.toThrow("Not authenticated");
    await expect(
      t.query(pullTransactions, { workspaceId: "global", afterRevision: 0, limit: 100 }),
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
    const first = await t.mutation(pushTransactions, {
      workspaceId: "global",
      operations: [txOp],
    });
    const duplicate = await t.mutation(pushTransactions, {
      workspaceId: "global",
      operations: [txOp],
    });
    expect(first.acknowledgements[0].applied).toBe(true);
    expect(duplicate.acknowledgements[0].applied).toBe(false);
    const result = await t.query(pullTransactions, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(result.entities).toHaveLength(1);
    expect(result.entities[0].name).toBe("Coffee");
    expect(result.latestRevision).toBe(1);
  });

  it("round-trips transaction and recurring currency metadata", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|currency-user",
    });
    await t.mutation(pushTransactions, {
      workspaceId: "global",
      operations: [
        {
          ...txOp,
          amountMinor: 227_611,
          currency: "INR",
          sourceCurrency: "USD",
          sourceAmountMinor: 2_360,
          exchangeRate: 96.44538771223525,
        },
      ],
    });
    await t.mutation(pushRecurring, {
      workspaceId: "global",
      operations: [
        {
          operationId: "op-recurring",
          workspaceId: "global",
          entityId: "recurring-1",
          version: { timestamp: 101, counter: 0, deviceId: "device-a" },
          deleted: false,
          name: "Cursor",
          amountMinor: 2_360,
          categoryId: "category-software",
          paymentMethodId: "payment-method-cash",
          frequency: "monthly",
          anchorDate: "2026-07-31",
          paused: false,
          currency: "USD",
        },
      ],
    });

    const txs = await t.query(pullTransactions, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    const recurring = await t.query(pullRecurring, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(txs.entities[0]).toMatchObject({
      currency: "INR",
      sourceCurrency: "USD",
      sourceAmountMinor: 2_360,
      exchangeRate: 96.44538771223525,
    });
    expect(recurring.entities[0]).toMatchObject({ currency: "USD", amountMinor: 2_360 });
  });

  it("keeps a newer tombstone over a stale update", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|user-a",
    });
    await t.mutation(pushTransactions, { workspaceId: "global", operations: [txOp] });
    await t.mutation(pushTransactions, {
      workspaceId: "global",
      operations: [
        {
          ...txOp,
          operationId: "delete",
          deleted: true,
          version: { ...txOp.version, timestamp: 200 },
        },
      ],
    });
    const stale = await t.mutation(pushTransactions, {
      workspaceId: "global",
      operations: [{ ...txOp, operationId: "stale", name: "Stale" }],
    });
    expect(stale.acknowledgements[0].applied).toBe(false);
    const result = await t.query(pullTransactions, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(result.entities[0].deleted).toBe(true);
  });

  it("isolates the same entity and revision stream between users", async () => {
    const base = convexTest(schema, modules);
    const alice = base.withIdentity({ tokenIdentifier: "https://api.workos.com/|alice" });
    const bob = base.withIdentity({ tokenIdentifier: "https://api.workos.com/|bob" });

    await alice.mutation(pushTransactions, { workspaceId: "global", operations: [txOp] });
    const bobBefore = await bob.query(pullTransactions, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(bobBefore.entities).toEqual([]);
    expect(bobBefore.latestRevision).toBe(0);

    await bob.mutation(pushTransactions, {
      workspaceId: "global",
      operations: [{ ...txOp, operationId: "bob-op", name: "Bob's coffee" }],
    });
    const aliceResult = await alice.query(pullTransactions, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    const bobResult = await bob.query(pullTransactions, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(aliceResult.entities[0].name).toBe("Coffee");
    expect(bobResult.entities[0].name).toBe("Bob's coffee");
    expect(aliceResult.latestRevision).toBe(1);
    expect(bobResult.latestRevision).toBe(1);
  });

  it("clears only the authenticated owner's workspace for a full re-upload", async () => {
    const base = convexTest(schema, modules);
    const alice = base.withIdentity({ tokenIdentifier: "https://api.workos.com/|alice" });
    const bob = base.withIdentity({ tokenIdentifier: "https://api.workos.com/|bob" });

    await alice.mutation(pushTransactions, { workspaceId: "global", operations: [txOp] });
    await bob.mutation(pushTransactions, {
      workspaceId: "global",
      operations: [{ ...txOp, operationId: "bob-op", name: "Bob's coffee" }],
    });

    const cleared = await alice.mutation(clearWorkspace, {
      workspaceId: "global",
      entityTypes: ["transaction"],
    });
    expect(cleared.deleted).toBe(1);
    expect(cleared.hasMore).toBe(false);

    const aliceAfter = await alice.query(pullTransactions, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(aliceAfter.entities).toEqual([]);
    expect(aliceAfter.latestRevision).toBe(0);

    const bobAfter = await bob.query(pullTransactions, {
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
    await t.mutation(pushTransactions, { workspaceId: "global", operations: [txOp] });
    await t.mutation(pushLends, {
      workspaceId: "global",
      operations: [
        {
          operationId: "lend-1",
          workspaceId: "global",
          entityId: "lend-1",
          version: { timestamp: 100, counter: 0, deviceId: "device-a" },
          deleted: false,
          contactName: "Sam",
          contactId: "cn-sam",
          amountMinor: 5000,
          occurredAt: 100,
          comment: "",
          kind: "lent",
        },
      ],
    });

    const cleared = await t.mutation(clearWorkspace, {
      workspaceId: "global",
      entityTypes: ["transaction", "category", "paymentMethod", "recurring", "preferences"],
    });
    expect(cleared.deleted).toBe(1);
    expect(cleared.hasMore).toBe(false);

    const txs = await t.query(pullTransactions, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    const lends = await t.query(pullLends, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(txs.entities).toHaveLength(0);
    expect(lends.entities).toHaveLength(1);
    expect(lends.entities[0].entityId).toBe("lend-1");
    expect(lends.latestRevision).toBe(2);
  });

  it("preserves native-owned emailMessage rows when clearing web-owned types", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|user-a",
    });
    await t.mutation(pushTransactions, { workspaceId: "global", operations: [txOp] });
    await t.mutation(pushEmailMessages, {
      workspaceId: "global",
      operations: [
        {
          operationId: "email-1",
          workspaceId: "global",
          entityId: "10:accountsubmsg-1",
          version: { timestamp: 100, counter: 0, deviceId: "device-a" },
          deleted: false,
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
          purchaseGroupId: "email-purchase-group-1",
          linkedTransactionId: "tx-1",
          reviewedAt: 100,
          createdAt: 100,
          updatedAt: 100,
        },
      ],
    });

    const cleared = await t.mutation(clearWorkspace, {
      workspaceId: "global",
      entityTypes: ["transaction", "category", "paymentMethod", "recurring", "preferences"],
    });
    expect(cleared.deleted).toBe(1);
    expect(cleared.hasMore).toBe(false);

    const emails = await t.query(pullEmailMessages, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(emails.entities).toHaveLength(1);
    expect(emails.entities[0]).toMatchObject({
      state: "added",
      purchaseGroupId: "email-purchase-group-1",
      linkedTransactionId: "tx-1",
      normalizedBodyText: "Full receipt body with every line of the email.",
    });
    expect(emails.latestRevision).toBe(2);
  });

  it("stores name and email on the workspace from auth and preferences", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|user-a",
      name: "Auth Name",
      email: "auth@example.com",
    });
    await t.mutation(pushTransactions, { workspaceId: "global", operations: [txOp] });
    const afterAuth = await t.run(async (ctx) => {
      return await ctx.db.query("workspaces").first();
    });
    expect(afterAuth?.name).toBe("Auth Name");
    expect(afterAuth?.email).toBe("auth@example.com");

    await t.mutation(pushPreferences, {
      workspaceId: "global",
      operations: [
        {
          operationId: "prefs-1",
          workspaceId: "global",
          entityId: "preferences",
          version: { timestamp: 200, counter: 0, deviceId: "device-a" },
          deleted: false,
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
      ],
    });
    const afterPrefs = await t.run(async (ctx) => {
      return await ctx.db.query("workspaces").first();
    });
    expect(afterPrefs?.name).toBe("Profile Name");
    expect(afterPrefs?.email).toBe("profile@example.com");
  });

  it("backfills workspace name and email on login for existing rows", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|user-a",
    });

    await t.run(async (ctx) => {
      await ctx.db.insert("workspaces", {
        ownerId: "https://api.workos.com/|user-a",
        workspaceId: "global",
        revision: 5,
      });
    });

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

describe("typed sync cross-table ordering", () => {
  it("orders revisions across typed tables from the shared workspace counter", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|cross-table",
    });
    await t.mutation(pushCategories, {
      workspaceId: "global",
      operations: [
        {
          operationId: "cat",
          workspaceId: "global",
          entityId: "category-1",
          version: { timestamp: 100, counter: 0, deviceId: "a" },
          deleted: false,
          name: "Food",
          emoji: "🍽",
          monthlyBudgetMinor: null,
          tint: "green",
          sortOrder: 0,
          system: false,
        },
      ],
    });
    await t.mutation(pushTransactions, {
      workspaceId: "global",
      operations: [
        {
          ...txOp,
          operationId: "tx",
          entityId: "transaction-1",
          version: { timestamp: 101, counter: 0, deviceId: "a" },
        },
      ],
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
  });

  it("delete on typed protocol tombstones the row", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|bridge-del",
    });
    await t.mutation(pushTransactions, {
      workspaceId: "global",
      operations: [
        {
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
        },
      ],
    });
    await t.mutation(pushTransactions, {
      workspaceId: "global",
      operations: [
        {
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
        },
      ],
    });

    const typed = await t.query(pullTransactions, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(typed.entities[0].deleted).toBe(true);
  });
});
