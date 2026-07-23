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
      for (const [date, rates, fetchedAt] of [
        ["2026-07-19", { INR: 90, USD: 1.1, EUR: 1 }, 1],
        ["2026-07-20", { INR: 91, USD: 1.12, EUR: 1 }, 2],
      ] as const) {
        for (const [currency, rate] of Object.entries(rates)) {
          await ctx.db.insert("exchangeRateEntries", {
            date,
            base: "EUR",
            currency,
            rate,
            fetchedAt,
          });
        }
      }
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
      await ctx.db.insert("exchangeRateEntries", {
        date: "2026-07-20",
        base: "EUR",
        currency: "INR",
        rate: 91,
        fetchedAt: Date.now(),
      });
      await ctx.db.insert("exchangeRateEntries", {
        date: "2026-07-20",
        base: "EUR",
        currency: "EUR",
        rate: 1,
        fetchedAt: Date.now(),
      });
    });
    const result = await t.action(refreshRates, {});
    expect(result).toEqual({ date: "2026-07-20", skipped: true });
  });
});

describe("exchangeRateEntries lookups", () => {
  it("rateOn prefers typed entries and falls back by date", async () => {
    const t = convexTest(schema, modules);
    const { rateOn } = await import("./exchangeRates");
    await t.run(async (ctx) => {
      await ctx.db.insert("exchangeRateEntries", {
        date: "2026-02-27",
        base: "EUR",
        currency: "USD",
        rate: 1,
        fetchedAt: 1,
      });
      await ctx.db.insert("exchangeRateEntries", {
        date: "2026-02-27",
        base: "EUR",
        currency: "INR",
        rate: 90,
        fetchedAt: 1,
      });
      await ctx.db.insert("exchangeRateEntries", {
        date: "2026-02-27",
        base: "EUR",
        currency: "EUR",
        rate: 1,
        fetchedAt: 1,
      });
      const ratio = await rateOn(ctx, "2026-02-28", "USD", "INR");
      expect(ratio).toBe(90);
    });
  });
});
