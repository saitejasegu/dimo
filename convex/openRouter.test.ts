import { describe, expect, it } from "vitest";
import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import schema from "./schema";
import { HOURLY_ANALYSIS_LIMIT } from "./openRouterLib";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);

const consumeAnalysisSlot = makeFunctionReference<
  "mutation",
  { ownerId: string; nowMs: number },
  {
    allowed: boolean;
    requestCount: number;
    retryAfterSeconds: number | null;
  }
>("openRouter:consumeAnalysisSlot");

const listFreeModels = makeFunctionReference<
  "action",
  Record<string, never>,
  Array<{ id: string; name: string }>
>("openRouter:listFreeModels");

describe("openRouter.consumeAnalysisSlot", () => {
  it("allows up to the hourly limit then blocks", async () => {
    const t = convexTest(schema, modules);
    const ownerId = "https://api.workos.com/|user-a";
    const nowMs = 1_700_000_000_000;

    for (let i = 1; i <= HOURLY_ANALYSIS_LIMIT; i += 1) {
      const result = await t.mutation(consumeAnalysisSlot, { ownerId, nowMs });
      expect(result.allowed).toBe(true);
      expect(result.requestCount).toBe(i);
    }

    const blocked = await t.mutation(consumeAnalysisSlot, { ownerId, nowMs });
    expect(blocked.allowed).toBe(false);
    expect(blocked.retryAfterSeconds).toBeGreaterThan(0);
  });

  it("resets after the hour window", async () => {
    const t = convexTest(schema, modules);
    const ownerId = "https://api.workos.com/|user-b";
    const nowMs = 1_700_000_000_000;

    await t.run(async (ctx) => {
      await ctx.db.insert("openRouterUsage", {
        ownerId,
        windowStartMs: nowMs,
        requestCount: HOURLY_ANALYSIS_LIMIT,
      });
    });

    const stillBlocked = await t.mutation(consumeAnalysisSlot, {
      ownerId,
      nowMs: nowMs + 60_000,
    });
    expect(stillBlocked.allowed).toBe(false);

    const reset = await t.mutation(consumeAnalysisSlot, {
      ownerId,
      nowMs: nowMs + 3_600_000,
    });
    expect(reset).toEqual({
      allowed: true,
      requestCount: 1,
      retryAfterSeconds: null,
    });
  });
});

describe("openRouter.listFreeModels", () => {
  it("requires authentication", async () => {
    const t = convexTest(schema, modules);
    await expect(t.action(listFreeModels, {})).rejects.toThrow(
      /Not authenticated/,
    );
  });
});
