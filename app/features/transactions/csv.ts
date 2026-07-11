import type { PaymentMethodOption } from "@/lib/types";

export const TRANSACTION_CSV_HEADERS = [
  "Date",
  "Note",
  "Amount",
  "Category",
  "Type",
] as const;

export interface TransactionCsvRow {
  occurredAt: number;
  merchant: string;
  amountMinor: number;
  category: string;
}

export interface TransactionCsvSource {
  name: string;
  category: string;
  amount: number;
  amountMinor?: number;
  occurredAt?: number;
}

export function defaultPaymentMethodIdForImport(
  paymentMethods: PaymentMethodOption[],
): string | null {
  return paymentMethods.find((method) => method.isDefault)?.id ?? null;
}

const CATEGORY_EMOJI_RULES: Array<[RegExp, string]> = [
  [/breakfast|lunch|dinner|dining|meal|restaurant|food/, "🍽️"],
  [/snack|coffee|cafe|tea|bakery/, "☕"],
  [/grocer|vegetable|fruit|milk|yogurt/, "🛒"],
  [/rent|house|home/, "🏠"],
  [/subscription|membership/, "🔁"],
  [/utilit|electric|water|gas|internet|phone|bill/, "💡"],
  [/movie|cinema|entertainment/, "🎬"],
  [/shopping|clothes|fashion/, "🛍️"],
  [/transport|transit|taxi|cab|fuel|petrol|travel/, "🚕"],
  [/health|medical|doctor|pharmacy/, "💊"],
  [/education|school|course|book/, "📚"],
  [/gift|donation/, "🎁"],
  [/laundry|cleaning/, "🧺"],
  [/fitness|gym|sport/, "🏋️"],
];

export function categoryEmojiForName(category: string): string {
  const normalized = category.trim().toLocaleLowerCase();
  return CATEGORY_EMOJI_RULES.find(([pattern]) => pattern.test(normalized))?.[1] ?? "💸";
}

function parseCsvRecords(input: string): string[][] {
  const records: string[][] = [];
  let record: string[] = [];
  let field = "";
  let quoted = false;

  for (let index = 0; index < input.length; index += 1) {
    const char = input[index];
    if (quoted) {
      if (char === '"' && input[index + 1] === '"') {
        field += '"';
        index += 1;
      } else if (char === '"') {
        quoted = false;
      } else {
        field += char;
      }
    } else if (char === '"') {
      quoted = true;
    } else if (char === ",") {
      record.push(field);
      field = "";
    } else if (char === "\n") {
      record.push(field);
      records.push(record);
      record = [];
      field = "";
    } else if (char !== "\r") {
      field += char;
    }
  }

  if (quoted) throw new Error("CSV contains an unclosed quoted field");
  record.push(field);
  if (record.some((value) => value.length > 0)) records.push(record);
  return records;
}

function parseDate(value: string): number {
  const trimmed = value.trim();
  const normalized = trimmed.replace(/ ([+-]\d{2})(\d{2})$/, " $1:$2");
  const timestamp = Date.parse(normalized);
  return timestamp;
}

function escapeCsvField(value: string): string {
  if (/[",\n\r]/.test(value)) return `"${value.replace(/"/g, '""')}"`;
  return value;
}

function pad2(value: number): string {
  return String(value).padStart(2, "0");
}

/** Format a timestamp in the same UTC style used by the import template. */
export function formatTransactionCsvDate(timestamp: number): string {
  const date = new Date(timestamp);
  return [
    `${date.getUTCFullYear()}-${pad2(date.getUTCMonth() + 1)}-${pad2(date.getUTCDate())}`,
    `${pad2(date.getUTCHours())}:${pad2(date.getUTCMinutes())}:${pad2(date.getUTCSeconds())}`,
    "+0000",
  ].join(" ");
}

export function formatTransactionCsvAmount(amountMinor: number): string {
  return (amountMinor / 100).toFixed(2);
}

/** Serialize transactions into Dimo's import/export CSV format. */
export function formatTransactionCsv(transactions: TransactionCsvSource[]): string {
  const rows = [...transactions]
    .sort((a, b) => (a.occurredAt ?? 0) - (b.occurredAt ?? 0))
    .map((transaction) => {
      const amountMinor = transaction.amountMinor ?? Math.round(transaction.amount * 100);
      return [
        formatTransactionCsvDate(transaction.occurredAt ?? 0),
        escapeCsvField(transaction.name),
        formatTransactionCsvAmount(amountMinor),
        escapeCsvField(transaction.category),
        "Expense",
      ].join(",");
    });

  return `${TRANSACTION_CSV_HEADERS.join(",")}\n${rows.length > 0 ? `${rows.join("\n")}\n` : ""}`;
}

export function parseTransactionCsv(input: string): TransactionCsvRow[] {
  const records = parseCsvRecords(input.replace(/^\uFEFF/, ""));
  if (records.length === 0) throw new Error("CSV is empty");

  const headers = records[0].map((value) => value.trim());
  if (
    headers.length !== TRANSACTION_CSV_HEADERS.length ||
    headers.some((value, index) => value !== TRANSACTION_CSV_HEADERS[index])
  ) {
    throw new Error(`Expected headers: ${TRANSACTION_CSV_HEADERS.join(", ")}`);
  }

  const rows: TransactionCsvRow[] = [];
  for (let index = 1; index < records.length; index += 1) {
    const record = records[index];
    if (record.every((value) => value.trim() === "")) continue;
    const rowNumber = index + 1;
    if (record.length !== TRANSACTION_CSV_HEADERS.length) {
      throw new Error(`Row ${rowNumber} must have exactly 5 columns`);
    }

    const [date, noteValue, amountValue, categoryValue, typeValue] = record;
    const occurredAt = parseDate(date);
    const merchant = noteValue.trim();
    const amount = Number(amountValue.trim());
    const category = categoryValue.trim();
    const type = typeValue.trim().toLowerCase();
    if (!Number.isFinite(occurredAt)) throw new Error(`Row ${rowNumber} has an invalid date`);
    if (!merchant) throw new Error(`Row ${rowNumber} has an empty note`);
    if (!Number.isFinite(amount) || amount <= 0) throw new Error(`Row ${rowNumber} has an invalid amount`);
    if (!category) throw new Error(`Row ${rowNumber} has an empty category`);
    if (type !== "expense") throw new Error(`Row ${rowNumber} type must be Expense`);

    rows.push({ occurredAt, merchant, amountMinor: Math.round(amount * 100), category });
  }

  if (rows.length === 0) throw new Error("CSV has no transactions");
  return rows;
}

export const TRANSACTION_CSV_TEMPLATE = `${TRANSACTION_CSV_HEADERS.join(",")}\n2026-07-11 11:38:08 +0000,Example purchase,354.00,Snacks,Expense\n`;
