import { describe, expect, it } from "vitest";
import type { Transaction } from "@/lib/types";
import {
  filterTransactions,
  paginateTransactionsByDay,
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

function tx(
  id: string,
  day: string,
  amount = 1,
): Transaction {
  return {
    id,
    name: `Merchant ${id}`,
    category: "Dining",
    time: "12:00 PM",
    day,
    amount,
  };
}

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

describe("paginateTransactionsByDay", () => {
  const list = [
    tx("1", "Today"),
    tx("2", "Today"),
    tx("3", "Yesterday"),
    tx("4", "Yesterday"),
    tx("5", "Yesterday"),
    tx("6", "Monday"),
  ];

  it("returns all items when under the limit", () => {
    expect(paginateTransactionsByDay(list, 50)).toEqual({
      items: list,
      hasMore: false,
    });
  });

  it("extends through the oldest included day", () => {
    expect(paginateTransactionsByDay(list, 3)).toEqual({
      items: list.slice(0, 5),
      hasMore: true,
    });
  });

  it("does not extend when the cut lands on a day boundary", () => {
    expect(paginateTransactionsByDay(list, 2)).toEqual({
      items: list.slice(0, 2),
      hasMore: true,
    });
  });

  it("reports no more when the extended page consumes the list", () => {
    expect(paginateTransactionsByDay(list.slice(0, 5), 3)).toEqual({
      items: list.slice(0, 5),
      hasMore: false,
    });
  });
});
