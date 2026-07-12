import { describe, expect, it } from "vitest";
import {
  categoryEmojiForName,
  defaultPaymentMethodIdForImport,
  formatTransactionCsv,
  parseTransactionCsv,
} from "@/features/transactions/csv";

describe("parseTransactionCsv", () => {
  it("parses the supported export format and quoted fields", () => {
    const rows = parseTransactionCsv(
      'Date,Note,Amount,Category,Type\r\n2026-07-11 11:38:08 +0000,"Coffee, cake",354.00,Snacks,Expense\r\n',
    );
    expect(rows).toEqual([{ occurredAt: Date.UTC(2026, 6, 11, 11, 38, 8), merchant: "Coffee, cake", amountMinor: 35400, category: "Snacks" }]);
  });

  it("parses date-only values as UTC midnight", () => {
    const rows = parseTransactionCsv(
      "Date,Note,Amount,Category,Type\n2026-07-11,Coffee,3.54,Snacks,Expense\n",
    );
    expect(rows[0]?.occurredAt).toBe(Date.UTC(2026, 6, 11));
  });

  it("rejects unsupported transaction types", () => {
    expect(() => parseTransactionCsv("Date,Note,Amount,Category,Type\n2026-07-11,Salary,100,Income,Income"))
      .toThrow("Row 2 type must be Expense");
  });

  it("assigns category-related emoji with an expense fallback", () => {
    expect(categoryEmojiForName("Movie snacks")).toBe("☕");
    expect(categoryEmojiForName("Utilities")).toBe("💡");
    expect(categoryEmojiForName("Something custom")).toBe("💸");
  });
});

describe("formatTransactionCsv", () => {
  it("exports transactions in the import format, oldest first", () => {
    const csv = formatTransactionCsv([
      {
        name: 'Bag "special"',
        category: "Dining, out",
        amount: 12.5,
        amountMinor: 1250,
        occurredAt: Date.UTC(2026, 6, 12, 9),
      },
      {
        name: "Coffee, cake",
        category: "Snacks",
        amount: 354,
        amountMinor: 35400,
        occurredAt: Date.UTC(2026, 6, 11, 11, 38, 8),
      },
    ]);

    expect(csv).toBe(
      'Date,Note,Amount,Category,Type\n' +
        '2026-07-11 11:38:08 +0000,"Coffee, cake",354.00,Snacks,Expense\n' +
        '2026-07-12 09:00:00 +0000,"Bag ""special""",12.50,"Dining, out",Expense\n',
    );
  });

  it("round-trips through parseTransactionCsv", () => {
    const csv = formatTransactionCsv([
      {
        name: "Coffee, cake",
        category: "Snacks",
        amount: 354,
        amountMinor: 35400,
        occurredAt: Date.UTC(2026, 6, 11, 11, 38, 8),
      },
    ]);
    expect(parseTransactionCsv(csv)).toEqual([
      { occurredAt: Date.UTC(2026, 6, 11, 11, 38, 8), merchant: "Coffee, cake", amountMinor: 35400, category: "Snacks" },
    ]);
  });
});


describe("defaultPaymentMethodIdForImport", () => {
  it("returns the configured default payment method", () => {
    expect(defaultPaymentMethodIdForImport([
      { id: "cash", name: "Cash", type: "Cash", detail: "", archived: false, isDefault: false },
      { id: "card", name: "Visa", type: "Card", detail: "42", archived: false, isDefault: true },
    ])).toBe("card");
  });

  it("returns null if no default payment method is available", () => {
    expect(defaultPaymentMethodIdForImport([])).toBeNull();
  });
});
