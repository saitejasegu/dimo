import { describe, expect, it } from "vitest";
import {
  convertMinor,
  minorUnitDigits,
  rateBetween,
  recurringEntryFields,
  recurringAmountInDefault,
  toMajorUnits,
  toMinorUnits,
  type RateTable,
} from "@/features/currency/rates";

// EUR-based table: 1 EUR = 90 INR = 1.1 USD = 160 JPY.
const rates: RateTable = {
  date: "2026-02-28",
  base: "EUR",
  rates: { INR: 90, USD: 1.1, JPY: 160 },
};

describe("rateBetween", () => {
  it("returns 1 for identical currencies without a table", () => {
    expect(rateBetween("INR", "INR", null)).toBe(1);
  });

  it("derives cross rates through the base", () => {
    // USD -> INR = 90 / 1.1
    expect(rateBetween("USD", "INR", rates)).toBeCloseTo(90 / 1.1, 6);
    // base EUR is implicitly 1
    expect(rateBetween("EUR", "INR", rates)).toBe(90);
  });

  it("returns null when a currency is missing", () => {
    expect(rateBetween("GBP", "INR", rates)).toBeNull();
    expect(rateBetween("USD", "INR", null)).toBeNull();
  });
});

describe("convertMinor", () => {
  it("converts USD cents into INR paise", () => {
    // $10.00 -> 1000 cents -> 10 * (90/1.1) = 818.18 INR -> 81818 paise
    expect(convertMinor(1000, "USD", "INR", rates)).toBe(81818);
  });

  it("honors JPY having zero minor-unit digits", () => {
    expect(minorUnitDigits("JPY")).toBe(0);
    // ¥1600 -> amountMinor 1600 (0 digits) -> /160 = 10 EUR -> 900 INR -> 90000 paise
    expect(convertMinor(1600, "JPY", "INR", rates)).toBe(90000);
    // EUR 10.00 (1000 minor) -> JPY 1600 major -> 1600 minor (0 digits)
    expect(convertMinor(1000, "EUR", "JPY", rates)).toBe(1600);
  });

  it("returns null when the rate is unavailable", () => {
    expect(convertMinor(1000, "GBP", "INR", rates)).toBeNull();
  });
});

describe("minor/major helpers", () => {
  it("round-trips through minor units per currency", () => {
    expect(toMinorUnits(12.34, "USD")).toBe(1234);
    expect(toMajorUnits(1234, "USD")).toBe(12.34);
    // JPY has no minor units
    expect(toMinorUnits(1500, "JPY")).toBe(1500);
    expect(toMajorUnits(1500, "JPY")).toBe(1500);
  });

  it("always records the recurring denomination, including the account default", () => {
    expect(recurringEntryFields(23.6, "USD")).toEqual({
      amountMinor: 2360,
      currency: "USD",
    });
    expect(recurringEntryFields(500, "INR")).toEqual({
      amountMinor: 50_000,
      currency: "INR",
    });
  });
});

describe("recurringAmountInDefault", () => {
  it("passes through a default-currency bill unchanged", () => {
    expect(recurringAmountInDefault({ amount: 500 }, "INR", rates)).toBe(500);
    expect(recurringAmountInDefault({ amount: 500, currency: "INR" }, "INR", rates)).toBe(500);
  });

  it("converts a foreign bill to the default currency", () => {
    // €10 (amountMinor 1000) -> 900 INR
    const value = recurringAmountInDefault(
      { amount: 10, amountMinor: 1000, currency: "EUR" },
      "INR",
      rates,
    );
    expect(value).toBe(900);
  });

  it("falls back to the raw amount when rates are unavailable", () => {
    expect(
      recurringAmountInDefault({ amount: 10, amountMinor: 1000, currency: "GBP" }, "INR", rates),
    ).toBe(10);
  });
});
