import type { EnterableCurrency } from "@/lib/types";

/**
 * Currency conversion for foreign-currency expense entry.
 *
 * Rates are ECB daily reference rates stored in Convex (`exchangeRates` table),
 * refreshed once per day by the `refreshRates` cron via Frankfurter. Clients
 * read `exchangeRates:latest` and keep a localStorage cache for offline use.
 */

/** Metadata for every currency a single expense may be entered in. */
export const CURRENCY_META: Record<
  EnterableCurrency,
  { symbol: string; label: string; minorUnitDigits: number }
> = {
  INR: { symbol: "₹", label: "INR", minorUnitDigits: 2 },
  USD: { symbol: "$", label: "USD", minorUnitDigits: 2 },
  EUR: { symbol: "€", label: "EUR", minorUnitDigits: 2 },
  GBP: { symbol: "£", label: "GBP", minorUnitDigits: 2 },
  JPY: { symbol: "¥", label: "JPY", minorUnitDigits: 0 },
  AUD: { symbol: "A$", label: "AUD", minorUnitDigits: 2 },
  CAD: { symbol: "C$", label: "CAD", minorUnitDigits: 2 },
  HKD: { symbol: "HK$", label: "HKD", minorUnitDigits: 2 },
  SGD: { symbol: "S$", label: "SGD", minorUnitDigits: 2 },
  CHF: { symbol: "CHF", label: "CHF", minorUnitDigits: 2 },
  CNY: { symbol: "¥", label: "CNY", minorUnitDigits: 2 },
};

export const ENTERABLE_CURRENCIES = Object.keys(CURRENCY_META) as EnterableCurrency[];

/** A snapshot of exchange rates for a single day, normalized to include the base. */
export interface RateTable {
  /** ECB rate date, `YYYY-MM-DD`. */
  date: string;
  /** Base currency the raw rates were quoted against. */
  base: string;
  /** Units of each currency per 1 unit of `base`; includes `base: 1`. */
  rates: Record<string, number>;
}

const CACHE_KEY = "dimo:exchangeRates";

export function isEnterableCurrency(value: string): value is EnterableCurrency {
  return value in CURRENCY_META;
}

/** Digits of minor units for a currency (2 for most, 0 for JPY). Defaults to 2. */
export function minorUnitDigits(currency: string): number {
  return CURRENCY_META[currency as EnterableCurrency]?.minorUnitDigits ?? 2;
}

function minorUnitFactor(currency: string): number {
  return 10 ** minorUnitDigits(currency);
}

/**
 * Major-unit exchange ratio to convert 1 unit of `from` into `to` using `rates`.
 * Returns `null` when either currency is missing from the table.
 */
export function rateBetween(
  from: string,
  to: string,
  rates: RateTable | null,
): number | null {
  if (from === to) return 1;
  if (!rates) return null;
  // The base currency is implicitly 1 even if it is not listed in `rates`.
  const unit = (code: string) => (code === rates.base ? 1 : rates.rates[code]);
  const fromRate = unit(from);
  const toRate = unit(to);
  if (!(fromRate > 0) || !(toRate > 0)) return null;
  return toRate / fromRate;
}

/**
 * Convert an integer minor-unit amount from one currency to another, honoring
 * each currency's minor-unit exponent (e.g. JPY has none). Returns `null` when
 * the rate is unavailable so callers can surface "rates unavailable" instead of
 * silently storing a wrong number.
 */
export function convertMinor(
  amountMinor: number,
  from: string,
  to: string,
  rates: RateTable | null,
): number | null {
  const ratio = rateBetween(from, to, rates);
  if (ratio == null) return null;
  const major = (amountMinor / minorUnitFactor(from)) * ratio;
  return Math.round(major * minorUnitFactor(to));
}

/** Convert a major-unit amount (what a user types) into minor units for `currency`. */
export function toMinorUnits(amount: number, currency: string): number {
  return Math.round(amount * minorUnitFactor(currency));
}

/** Convert an integer minor-unit amount back into major units for `currency`. */
export function toMajorUnits(amountMinor: number, currency: string): number {
  return amountMinor / minorUnitFactor(currency);
}

/** Canonical fields for a recurring definition. New rows always name their denomination. */
export function recurringEntryFields(amount: number, currency: EnterableCurrency) {
  return {
    amountMinor: Math.max(1, toMinorUnits(amount, currency)),
    currency,
  } as const;
}

/**
 * A recurring bill's amount expressed in major units of `defaultCurrency`, using
 * today's rates. Bills already in the default currency (or with rates
 * unavailable) return their raw amount so totals still render.
 */
export function recurringAmountInDefault(
  rec: { amount: number; amountMinor?: number; currency?: string },
  defaultCurrency: string,
  rates: RateTable | null,
): number {
  if (!rec.currency || rec.currency === defaultCurrency) return rec.amount;
  const sourceMinor = rec.amountMinor ?? toMinorUnits(rec.amount, rec.currency);
  const converted = convertMinor(sourceMinor, rec.currency, defaultCurrency, rates);
  return converted == null ? rec.amount : toMajorUnits(converted, defaultCurrency);
}

/** Read the last cached rate table from localStorage, or `null`. */
export function loadCachedRates(): RateTable | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(CACHE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as RateTable;
    if (parsed && typeof parsed.base === "string" && parsed.rates) return parsed;
  } catch {
    // Corrupt cache — ignore and refetch from Convex.
  }
  return null;
}

/** Persist a rate table for offline use. */
export function cacheRates(table: RateTable) {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(CACHE_KEY, JSON.stringify(table));
  } catch {
    // Storage full / unavailable — non-fatal, we keep the in-memory table.
  }
}
