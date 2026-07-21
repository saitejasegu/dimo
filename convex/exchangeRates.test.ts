import { describe, expect, it } from "vitest";
import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import schema from "./schema";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
const latest = makeFunctionReference<"query", Record<string, never>, {
  date: string;
  base: string;
  rates: Record<string, number>;
} | null>("exchangeRates:latest");
const refreshRates = makeFunctionReference<"action", Record<string, never>, {
  date: string;
  skipped: boolean;
}>("exchangeRates:refreshRates");

describe("exchangeRates.latest", () => {
  it("requires authentication", async () => {
    const t = convexTest(schema, modules);
    await expect(t.query(latest, {})).rejects.toThrow(/Not authenticated/);
  });

  it("returns null when no rates are stored", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|user-a",
    });
    expect(await t.query(latest, {})).toBeNull();
  });

  it("returns the most recent row with base normalized into rates", async () => {
    const t = convexTest(schema, modules).withIdentity({
      tokenIdentifier: "https://api.workos.com/|user-a",
    });
    await t.run(async (ctx) => {
      await ctx.db.insert("exchangeRates", {
        date: "2026-07-19",
        base: "EUR",
        rates: { INR: 90, USD: 1.1 },
        fetchedAt: 1,
      });
      await ctx.db.insert("exchangeRates", {
        date: "2026-07-20",
        base: "EUR",
        rates: { INR: 91, USD: 1.12 },
        fetchedAt: 2,
      });
    });
    expect(await t.query(latest, {})).toEqual({
      date: "2026-07-20",
      base: "EUR",
      rates: { INR: 91, USD: 1.12, EUR: 1 },
    });
  });
});

describe("exchangeRates.refreshRates", () => {
  it("skips Frankfurter when rates were already fetched today", async () => {
    const t = convexTest(schema, modules);
    await t.run(async (ctx) => {
      await ctx.db.insert("exchangeRates", {
        date: "2026-07-20",
        base: "EUR",
        rates: { INR: 91 },
        fetchedAt: Date.now(),
      });
    });
    const result = await t.action(refreshRates, {});
    expect(result).toEqual({ date: "2026-07-20", skipped: true });
  });
});
