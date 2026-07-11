import { describe, expect, it } from "vitest";
import type { Transaction } from "@/lib/types";
import {
  filterTransactions,
  paymentMethodFilterOptions,
} from "@/features/transactions/selectors";

const transactions: Transaction[] = [
  {
    id: "1",
    name: "Cafe",
    category: "Dining",
    time: "9:00 AM",
    day: "Today",
    amount: 12,
    paymentMethod: "Card · Visa · ••42",
  },
  {
    id: "2",
    name: "Market",
    category: "Groceries",
    time: "10:00 AM",
    day: "Today",
    amount: 30,
    paymentMethod: "Cash",
  },
  {
    id: "3",
    name: "Bakery",
    category: "Dining",
    time: "11:00 AM",
    day: "Today",
    amount: 8,
    paymentMethod: "Cash",
  },
];

describe("transaction payment method filters", () => {
  it("returns unique payment methods in label order", () => {
    expect(paymentMethodFilterOptions(transactions)).toEqual([
      "Card · Visa · ••42",
      "Cash",
    ]);
  });

  it("combines payment method, category, and search filters", () => {
    expect(
      filterTransactions(transactions, {
        categories: ["Dining"],
        paymentMethod: "Cash",
        query: "bake",
      }).map((transaction) => transaction.id),
    ).toEqual(["3"]);
  });

  it("matches any of multiple selected categories", () => {
    expect(
      filterTransactions(transactions, {
        categories: ["Dining", "Groceries"],
        paymentMethod: "All",
        query: "",
      }).map((transaction) => transaction.id),
    ).toEqual(["1", "2", "3"]);
  });

  it("treats no selected categories as all categories", () => {
    expect(
      filterTransactions(transactions, {
        categories: [],
        paymentMethod: "All",
        query: "",
      }),
    ).toEqual(transactions);
  });
});
