import { CURRENCY_META } from "@/features/currency/rates";

/**
 * Symbol for any currency (account default or a foreign entry currency). Falls
 * back to the currency code itself for anything outside the enterable set.
 */
function symbolFor(currency: string): string {
  return CURRENCY_META[currency as keyof typeof CURRENCY_META]?.symbol ?? currency;
}

/**
 * Built once per process: `money` runs per row, per chart bar and per category, and
 * constructing an `Intl.NumberFormat` costs far more than formatting with one.
 * Mirrors the two cached formatters in `ios-native/Dimo/Domain/Formatting.swift`.
 */
const integerMoneyFormat = new Intl.NumberFormat("en-IN", {
  minimumFractionDigits: 0,
  maximumFractionDigits: 0,
});
const fractionalMoneyFormat = new Intl.NumberFormat("en-IN", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

/**
 * Format a whole-number amount with the given currency symbol.
 * Currency is INR by default to match the design's locale-grouped output.
 */
export function money(amount: number, currency: string = "INR"): string {
  const symbol = symbolFor(currency);
  const hasFraction = Math.abs(amount % 1) > 0.0001;
  const format = hasFraction ? fractionalMoneyFormat : integerMoneyFormat;
  return (amount < 0 ? "−" : "") + symbol + format.format(Math.abs(amount));
}

/** Money prefixed with a minus sign, used for outgoing transaction amounts. */
export function spent(amount: number, currency: string = "INR"): string {
  return "−" + money(amount, currency);
}

/** Rounded integer percentage. Not clamped — overspend can exceed 100. */
export function percent(value: number, total: number): number {
  if (total <= 0) return 0;
  return Math.round((value / total) * 100);
}

/** Compact money for chart labels, e.g. 9200 -> "₹9.2k". */
export function compactMoney(amount: number, currency: string = "INR"): string {
  const symbol = symbolFor(currency);
  if (amount >= 1000) {
    return symbol + (amount / 1000).toFixed(1).replace(/\.0$/, "") + "k";
  }
  return symbol + Number(amount.toFixed(2)).toString();
}

export function currencySymbol(currency: string = "INR"): string {
  return symbolFor(currency);
}
