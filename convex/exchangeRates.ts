import {
  internalActionGeneric,
  internalMutationGeneric,
  internalQueryGeneric,
  queryGeneric,
} from "convex/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";

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

/** Reconstruct a rates map for a date from typed exchangeRateEntries. */
async function ratesMapForDate(
  ctx: { db: any },
  date: string,
): Promise<RatesRow | null> {
  const entries = await ctx.db
    .query("exchangeRateEntries")
    .withIndex("by_date", (q: any) => q.eq("date", date))
    .take(64);
  if (entries.length === 0) return null;
  const rates: Record<string, number> = {};
  let base = RATE_BASE;
  let fetchedAt = 0;
  for (const entry of entries) {
    rates[entry.currency] = entry.rate;
    base = entry.base;
    fetchedAt = Math.max(fetchedAt, entry.fetchedAt);
  }
  rates[base] = 1;
  return { date, base, rates, fetchedAt };
}

async function latestRatesDateOnOrBefore(
  ctx: { db: any },
  dateKey: string,
): Promise<string | null> {
  const exact = await ctx.db
    .query("exchangeRateEntries")
    .withIndex("by_date_currency", (q: any) =>
      q.eq("date", dateKey).eq("currency", RATE_BASE),
    )
    .unique();
  if (exact) return exact.date;

  // Fallback: scan by_date descending for any currency on/before dateKey.
  const prior = await ctx.db
    .query("exchangeRateEntries")
    .withIndex("by_date", (q: any) => q.lte("date", dateKey))
    .order("desc")
    .first();
  return prior?.date ?? null;
}

/**
 * Major-unit ratio to convert 1 unit of `from` into `to` using typed entries
 * (and legacy blob as last-resort fallback during dual-write).
 */
export async function rateOn(
  ctx: { db: any },
  dateKey: string,
  from: string,
  to: string,
): Promise<number | null> {
  if (from === to) return 1;

  const date = await latestRatesDateOnOrBefore(ctx, dateKey);
  if (date) {
    const fromEntry =
      from === RATE_BASE
        ? { rate: 1 }
        : await ctx.db
            .query("exchangeRateEntries")
            .withIndex("by_date_currency", (q: any) =>
              q.eq("date", date).eq("currency", from),
            )
            .unique();
    const toEntry =
      to === RATE_BASE
        ? { rate: 1 }
        : await ctx.db
            .query("exchangeRateEntries")
            .withIndex("by_date_currency", (q: any) =>
              q.eq("date", date).eq("currency", to),
            )
            .unique();
    // Also allow looking up the base row when from/to equals stored base.
    const row = await ratesMapForDate(ctx, date);
    if (row) {
      const unit = (code: string) => (code === row.base ? 1 : row.rates[code]);
      const fromRate = unit(from);
      const toRate = unit(to);
      if (fromRate > 0 && toRate > 0) return toRate / fromRate;
    }
    if (fromEntry && toEntry && fromEntry.rate > 0 && toEntry.rate > 0) {
      return toEntry.rate / fromEntry.rate;
    }
  }

  // Legacy blob fallback for pre-backfill rows.
  const exact = await ctx.db
    .query("exchangeRates")
    .withIndex("by_date", (q: any) => q.eq("date", dateKey))
    .unique();
  const legacy =
    exact ??
    (await ctx.db
      .query("exchangeRates")
      .withIndex("by_date", (q: any) => q.lte("date", dateKey))
      .order("desc")
      .first());
  if (!legacy) return null;
  const unit = (code: string) => (code === legacy.base ? 1 : legacy.rates[code]);
  const fromRate = unit(from);
  const toRate = unit(to);
  if (!(fromRate > 0) || !(toRate > 0)) return null;
  return toRate / fromRate;
}

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

function normalizeRatesRow(row: RatesRow) {
  return {
    date: row.date,
    base: row.base,
    rates: { ...row.rates, [row.base]: 1 },
  };
}

/** Write typed entries + mirror legacy blob row. */
export const upsertRates = internalMutationGeneric({
  args: {
    date: v.string(),
    base: v.string(),
    rates: v.record(v.string(), v.number()),
  },
  handler: async (ctx, args) => {
    const fetchedAt = Date.now();
    const currencies = new Set([...Object.keys(args.rates), args.base]);
    for (const currency of currencies) {
      const rate = currency === args.base ? 1 : args.rates[currency];
      if (!(rate > 0)) continue;
      const existing = await ctx.db
        .query("exchangeRateEntries")
        .withIndex("by_date_currency", (q: any) =>
          q.eq("date", args.date).eq("currency", currency),
        )
        .unique();
      const fields = {
        date: args.date,
        base: args.base,
        currency,
        rate,
        fetchedAt,
      };
      if (existing) await ctx.db.patch(existing._id, fields);
      else await ctx.db.insert("exchangeRateEntries", fields);
    }

    // Mirror legacy blob for Android / old clients.
    const blob = await ctx.db
      .query("exchangeRates")
      .withIndex("by_date", (q: any) => q.eq("date", args.date))
      .unique();
    const blobFields = {
      date: args.date,
      base: args.base,
      rates: args.rates,
      fetchedAt,
    };
    if (blob) await ctx.db.patch(blob._id, blobFields);
    else await ctx.db.insert("exchangeRates", blobFields);
    return null;
  },
});

/** Most recent stored rates row (internal; used by refresh skip + public latest). */
export const latestRow = internalQueryGeneric({
  args: {},
  handler: async (ctx) => {
    const latestEntry = await ctx.db
      .query("exchangeRateEntries")
      .withIndex("by_date")
      .order("desc")
      .first();
    if (latestEntry) {
      return await ratesMapForDate(ctx, latestEntry.date);
    }
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
    const latestEntry = await ctx.db
      .query("exchangeRateEntries")
      .withIndex("by_date")
      .order("desc")
      .first();
    if (latestEntry) {
      const row = await ratesMapForDate(ctx, latestEntry.date);
      return row ? normalizeRatesRow(row) : null;
    }
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
