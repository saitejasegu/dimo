import type { Currency } from "@/lib/types";

const CURRENCY_SYMBOL: Record<Currency, string> = {
  INR: "₹",
  USD: "$",
  EUR: "€",
};

/**
 * Format a whole-number amount with the given currency symbol.
 * Currency is INR by default to match the design's locale-grouped output.
 */
export function money(amount: number, currency: Currency = "INR"): string {
  const symbol = CURRENCY_SYMBOL[currency] ?? "₹";
  const hasFraction = Math.abs(amount % 1) > 0.0001;
  return symbol + amount.toLocaleString("en-IN", {
    minimumFractionDigits: hasFraction ? 2 : 0,
    maximumFractionDigits: 2,
  });
}

/** Money prefixed with a minus sign, used for outgoing transaction amounts. */
export function spent(amount: number, currency: Currency = "INR"): string {
  return "−" + money(amount, currency);
}

/** Rounded integer percentage, clamped to [0, 100]. */
export function percent(value: number, total: number): number {
  if (total <= 0) return 0;
  return Math.min(100, Math.round((value / total) * 100));
}

/** Compact money for chart labels, e.g. 9200 -> "₹9.2k". */
export function compactMoney(amount: number, currency: Currency = "INR"): string {
  const symbol = CURRENCY_SYMBOL[currency] ?? "₹";
  if (amount >= 1000) {
    return symbol + (amount / 1000).toFixed(1).replace(/\.0$/, "") + "k";
  }
  return symbol + Number(amount.toFixed(2)).toString();
}

export function currencySymbol(currency: Currency = "INR"): string {
  return CURRENCY_SYMBOL[currency] ?? "₹";
}
