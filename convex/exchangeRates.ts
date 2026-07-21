import {
  internalActionGeneric,
  internalMutationGeneric,
  internalQueryGeneric,
  queryGeneric,
} from "convex/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";

/* Generic Convex functions intentionally use untyped index builders until a
   deployment is linked and Convex generates its schema-specific bindings. */
/* eslint-disable @typescript-eslint/no-explicit-any */

const FRANKFURTER_BASE = "https://api.frankfurter.dev/v1";
const RATE_BASE = "EUR";

type AuthIdentity = {
  tokenIdentifier: string;
};

async function requireIdentity(ctx: {
  auth: { getUserIdentity(): Promise<AuthIdentity | null> };
}) {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) throw new Error("Not authenticated");
  return identity;
}

function utcDateKey(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

function normalizeRatesRow(row: RatesRow) {
  return {
    date: row.date,
    base: row.base,
    rates: { ...row.rates, [row.base]: 1 },
  };
}

// Currencies the app can enter and therefore must convert. Kept in sync with
// `app/features/currency/rates.ts` (Convex must not import from the app tree).
const SUPPORTED_CURRENCIES = [
  "INR",
  "USD",
  "EUR",
  "GBP",
  "JPY",
  "AUD",
  "CAD",
  "HKD",
  "SGD",
  "CHF",
  "CNY",
];

type RatesRow = {
  date: string;
  base: string;
  rates: Record<string, number>;
  fetchedAt: number;
};

// Minor-unit digits per currency (2 for most, 0 for JPY). Mirrors
// CURRENCY_META in `app/features/currency/rates.ts`.
const MINOR_UNIT_DIGITS: Record<string, number> = { JPY: 0 };

export function minorUnitDigits(code: string): number {
  return MINOR_UNIT_DIGITS[code] ?? 2;
}

/**
 * Convert an integer minor-unit amount using a known major-unit ratio, honoring
 * each currency's minor-unit exponent.
 */
export function convertMinorAmount(
  amountMinor: number,
  from: string,
  to: string,
  ratio: number,
): number {
  const major = (amountMinor / 10 ** minorUnitDigits(from)) * ratio;
  return Math.round(major * 10 ** minorUnitDigits(to));
}

/**
 * Major-unit ratio to convert 1 unit of `from` into `to` using a stored rates
 * row. The base currency is implicitly 1. Returns `null` when a currency is
 * missing so callers can fall back rather than store a wrong amount.
 */
export function ratioFromRow(
  row: Pick<RatesRow, "base" | "rates">,
  from: string,
  to: string,
): number | null {
  if (from === to) return 1;
  const unit = (code: string) => (code === row.base ? 1 : row.rates[code]);
  const fromRate = unit(from);
  const toRate = unit(to);
  if (!(fromRate > 0) || !(toRate > 0)) return null;
  return toRate / fromRate;
}

/**
 * Look up the conversion ratio for `dateKey`, falling back to the most recent
 * row on or before that date. Returns `null` when no usable rate exists.
 */
export async function rateOn(
  ctx: { db: any },
  dateKey: string,
  from: string,
  to: string,
): Promise<number | null> {
  if (from === to) return 1;
  const exact = await ctx.db
    .query("exchangeRates")
    .withIndex("by_date", (q: any) => q.eq("date", dateKey))
    .unique();
  const row: RatesRow | null =
    exact ??
    (await ctx.db
      .query("exchangeRates")
      .withIndex("by_date", (q: any) => q.lte("date", dateKey))
      .order("desc")
      .first());
  if (!row) return null;
  return ratioFromRow(row, from, to);
}

export const upsertRates = internalMutationGeneric({
  args: {
    date: v.string(),
    base: v.string(),
    rates: v.record(v.string(), v.number()),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("exchangeRates")
      .withIndex("by_date", (q: any) => q.eq("date", args.date))
      .unique();
    const fields = {
      date: args.date,
      base: args.base,
      rates: args.rates,
      fetchedAt: Date.now(),
    };
    if (existing) {
      await ctx.db.patch(existing._id, fields);
    } else {
      await ctx.db.insert("exchangeRates", fields);
    }
    return null;
  },
});

/** Most recent stored rates row (internal; used by refresh skip + public latest). */
export const latestRow = internalQueryGeneric({
  args: {},
  handler: async (ctx) => {
    return (await ctx.db
      .query("exchangeRates")
      .withIndex("by_date")
      .order("desc")
      .first()) as RatesRow | null;
  },
});

/**
 * Latest ECB rates for authenticated clients. Frankfurter is only contacted by
 * the daily `refreshRates` cron — clients never call the external API.
 */
export const latest = queryGeneric({
  args: {},
  handler: async (ctx) => {
    await requireIdentity(ctx);
    const row = (await ctx.db
      .query("exchangeRates")
      .withIndex("by_date")
      .order("desc")
      .first()) as RatesRow | null;
    return row ? normalizeRatesRow(row) : null;
  },
});

export const refreshRates = internalActionGeneric({
  args: {},
  handler: async (ctx): Promise<{ date: string; skipped: boolean }> => {
    // One Frankfurter call per UTC day — skip if we already fetched today.
    const existing: RatesRow | null = await ctx.runQuery(
      internal.exchangeRates.latestRow,
      {},
    );
    if (existing && utcDateKey(existing.fetchedAt) === utcDateKey(Date.now())) {
      return { date: existing.date, skipped: true };
    }

    const symbols = SUPPORTED_CURRENCIES.filter((code) => code !== RATE_BASE).join(",");
    const response = await fetch(
      `${FRANKFURTER_BASE}/latest?base=${RATE_BASE}&symbols=${symbols}`,
    );
    if (!response.ok) {
      throw new Error(`Frankfurter request failed: ${response.status}`);
    }
    const body = (await response.json()) as {
      base: string;
      date: string;
      rates: Record<string, number>;
    };
    await ctx.runMutation(internal.exchangeRates.upsertRates, {
      date: body.date,
      base: body.base,
      rates: body.rates,
    });
    return { date: body.date, skipped: false };
  },
});
