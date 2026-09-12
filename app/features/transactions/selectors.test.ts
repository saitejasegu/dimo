import { describe, expect, it } from "vitest";
import type { Transaction } from "@/lib/types";
import {
  filterTransactions,
  merchantSuggestions,
  suggestionCategory,
  paginateTransactionsByDay,
  paymentMethodFilterOptions,
  pickerCategoryNames,
  transactionsForActiveCategories,
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

describe("archived category pickers", () => {
  const categories = [
    { name: "Dining", archived: false },
    { name: "Travel", archived: true },
    { name: "Bills", archived: false },
  ];

  it("omits archived categories from new-expense pickers", () => {
    expect(pickerCategoryNames(categories)).toEqual(["Dining", "Bills"]);
  });

  it("keeps an archived category selectable while editing a record that uses it", () => {
    expect(pickerCategoryNames(categories, "Travel")).toEqual([
      "Dining",
      "Bills",
      "Travel",
    ]);
  });

  it("drops archived-category spend from the per-category budget rows", () => {
    const rows = [
      { id: "1", categoryId: "dining" },
      { id: "2", categoryId: "travel" },
      { id: "3", categoryId: "bills" },
    ];
    expect(
      transactionsForActiveCategories(rows, [
        { id: "dining", archived: false },
        { id: "travel", archived: true },
        { id: "bills" },
      ]).map((row) => row.id),
    ).toEqual(["1", "3"]);
  });
});

describe("expense suggestion categories", () => {
  const categories = [
    { id: "old", name: "Dining", archived: true },
    { id: "new", name: "Dining", archived: false },
    { id: "bills", name: "Bills", archived: false },
  ];

  it("keeps the latest category ID and rejects archived categories sharing an active name", () => {
    const [suggestion] = merchantSuggestions([
      { ...transactions[0], categoryId: "new", occurredAt: 1 },
      { ...transactions[0], id: "later", categoryId: "old", occurredAt: 2 },
    ], "caf");
    expect(suggestion).toMatchObject({ name: "Cafe", categoryId: "old", count: 2 });
    expect(suggestionCategory(suggestion, categories)).toBeUndefined();
  });

  it("resolves active categories by ID, including renamed categories", () => {
    expect(suggestionCategory({ name: "Cafe", category: "Old name", categoryId: "new", count: 1 }, categories)).toBe("Dining");
  });

  it("supports legacy names and rejects missing categories", () => {
    expect(suggestionCategory({ name: "Bill", category: "Bills", count: 1 }, categories)).toBe("Bills");
    expect(suggestionCategory({ name: "Cafe", category: "Dining", count: 1 }, categories)).toBeUndefined();
    expect(suggestionCategory({ name: "Cafe", category: "Dining", categoryId: "missing", count: 1 }, categories)).toBeUndefined();
  });
});
