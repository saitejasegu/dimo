import { describe, expect, it } from "vitest";
import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import schema from "./schema";
import {
  DEFAULT_TOMBSTONE_RETENTION_DAYS,
  retentionDays,
} from "./tombstonePurge";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
const push = makeFunctionReference<"mutation">("sync:push");
const pull = makeFunctionReference<"query">("sync:pull");
const purgeExpired = makeFunctionReference<"mutation">(
  "tombstonePurge:purgeExpired",
);

const MS_PER_DAY = 24 * 60 * 60 * 1000;

function transactionOp(overrides: Record<string, unknown> = {}) {
  return {
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
    ...overrides,
  };
}

describe("tombstone retentionDays", () => {
  it("defaults to 90 when unset or invalid", () => {
    expect(retentionDays(undefined)).toBe(DEFAULT_TOMBSTONE_RETENTION_DAYS);
    expect(retentionDays("")).toBe(DEFAULT_TOMBSTONE_RETENTION_DAYS);
    expect(retentionDays("  ")).toBe(DEFAULT_TOMBSTONE_RETENTION_DAYS);
    expect(retentionDays("0")).toBe(DEFAULT_TOMBSTONE_RETENTION_DAYS);
    expect(retentionDays("-3")).toBe(DEFAULT_TOMBSTONE_RETENTION_DAYS);
    expect(retentionDays("nope")).toBe(DEFAULT_TOMBSTONE_RETENTION_DAYS);
  });

  it("parses positive integer day counts", () => {
    expect(retentionDays("30")).toBe(30);
    expect(retentionDays("180")).toBe(180);
  });
});

describe("tombstonePurge.purgeExpired", () => {
  it("keeps fresh tombstones and live rows; hard-deletes expired tombstones", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|purge-user",
    });

    const now = Date.UTC(2026, 6, 22);
    const freshTs = now - 10 * MS_PER_DAY;
    const expiredTs = now - (DEFAULT_TOMBSTONE_RETENTION_DAYS + 5) * MS_PER_DAY;

    await t.mutation(push, {
      workspaceId: "global",
      operations: [
        transactionOp({
          operationId: "live",
          entityId: "transaction-live",
          version: { timestamp: now, counter: 0, deviceId: "device-a" },
          payload: {
            id: "transaction-live",
            name: "Live",
            amountMinor: 100,
            occurredAt: now,
            categoryId: "category-dining",
            paymentMethodId: "payment-method-cash",
          },
          deleted: false,
        }),
        transactionOp({
          operationId: "fresh-delete",
          entityId: "transaction-fresh",
          version: { timestamp: freshTs, counter: 0, deviceId: "device-a" },
          payload: {
            id: "transaction-fresh",
            name: "Fresh",
            amountMinor: 200,
            occurredAt: freshTs,
            categoryId: "category-dining",
            paymentMethodId: "payment-method-cash",
          },
          deleted: true,
        }),
        transactionOp({
          operationId: "expired-delete",
          entityId: "transaction-expired",
          version: { timestamp: expiredTs, counter: 0, deviceId: "device-a" },
          payload: {
            id: "transaction-expired",
            name: "Expired",
            amountMinor: 300,
            occurredAt: expiredTs,
            categoryId: "category-dining",
            paymentMethodId: "payment-method-cash",
          },
          deleted: true,
        }),
      ],
    });

    const before = await t.query(pull, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    expect(before.entities).toHaveLength(3);

    const result = await t.mutation(purgeExpired, { now });
    expect(result.purged).toBe(1);
    expect(result.hasMore).toBe(false);
    expect(result.days).toBe(DEFAULT_TOMBSTONE_RETENTION_DAYS);

    const after = await t.query(pull, {
      workspaceId: "global",
      afterRevision: 0,
      limit: 100,
    });
    const ids = after.entities.map((row: { entityId: string }) => row.entityId).sort();
    expect(ids).toEqual(["transaction-fresh", "transaction-live"]);
    expect(
      after.entities.find((row: { entityId: string }) => row.entityId === "transaction-fresh")
        ?.deleted,
    ).toBe(true);
    expect(
      after.entities.find((row: { entityId: string }) => row.entityId === "transaction-live")
        ?.deleted,
    ).toBe(false);
  });
});
