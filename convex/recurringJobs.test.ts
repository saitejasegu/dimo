import { describe, expect, it } from "vitest";
import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import schema from "./schema";
import {
  istDateKey,
  isRecurringDueOn,
  occurrenceTimestampIST,
  recurringTransactionId,
} from "./recurringJobs";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
const materializeDue = makeFunctionReference<"mutation">(
  "recurringJobs:materializeDue",
);

function recurringOperation(id: string, overrides: Record<string, unknown> = {}) {
  return {
    operationId: `op-${id}`,
    workspaceId: "global",
    entityType: "recurring" as const,
    entityId: id,
    version: { timestamp: 100, counter: 0, deviceId: "device-a" },
    payload: {
      id,
      name: "Rent",
      amountMinor: 50_000,
      categoryId: "category-home",
      paymentMethodId: "payment-method-cash",
      frequency: "monthly" as const,
      anchorDate: "2026-01-31",
      paused: false,
      ...overrides,
    },
    deleted: false,
  };
}

describe("recurring materialization", () => {
  it("derives the calendar day in IST", () => {
    expect(istDateKey(Date.parse("2026-07-13T18:29:59.000Z"))).toBe(
      "2026-07-13",
    );
    expect(istDateKey(Date.parse("2026-07-13T18:30:00.000Z"))).toBe(
      "2026-07-14",
    );
  });

  it("compares recurrence calendar dates without a time component", () => {
    expect(
      isRecurringDueOn(
        { anchorDate: "2026-01-31", frequency: "monthly" },
        "2026-02-28",
      ),
    ).toBe(true);
    expect(
      isRecurringDueOn(
        { anchorDate: "2026-01-31", frequency: "monthly" },
        "2026-02-27",
      ),
    ).toBe(false);
    expect(
      isRecurringDueOn(
        { anchorDate: "2024-02-29", frequency: "yearly" },
        "2026-02-28",
      ),
    ).toBe(true);
  });

  it("encodes generated occurrences at noon IST", () => {
    expect(new Date(occurrenceTimestampIST("2026-07-13")).toISOString()).toBe(
      "2026-07-13T06:30:00.000Z",
    );
  });

  it("creates one sync-visible transaction and is idempotent", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|user-a",
    });
    const push = makeFunctionReference<"mutation">("sync:push");
    const pull = makeFunctionReference<"query">("sync:pull");
    await t.mutation(push, {
      workspaceId: "global",
      operations: [recurringOperation("rent")],
    });

    const first = await t.mutation(materializeDue, {
      dateKey: "2026-02-28",
      cursor: null,
    });
    const second = await t.mutation(materializeDue, {
      dateKey: "2026-02-28",
      cursor: null,
    });
    expect(first.created).toBe(1);
    expect(second.created).toBe(0);

    const result = await t.query(pull, {
      workspaceId: "global",
      afterRevision: 1,
      limit: 100,
    });
    expect(result.entities).toHaveLength(1);
    expect(result.entities[0]).toMatchObject({
      entityType: "transaction",
      entityId: recurringTransactionId("rent", "2026-02-28"),
      serverRevision: 2,
      payload: {
        name: "Rent",
        occurredAt: occurrenceTimestampIST("2026-02-28"),
      },
    });
    expect(result.latestRevision).toBe(2);
  });

  it("skips paused and not-due recurring entries", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|user-a",
    });
    const push = makeFunctionReference<"mutation">("sync:push");
    await t.mutation(push, {
      workspaceId: "global",
      operations: [
        recurringOperation("paused", { paused: true }),
        recurringOperation("later", { anchorDate: "2026-03-31" }),
      ],
    });
    const result = await t.mutation(materializeDue, {
      dateKey: "2026-02-28",
      cursor: null,
    });
    expect(result.created).toBe(0);
  });
});
