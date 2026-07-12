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

const CSV_DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?)?(?:\s*(Z|[+-]\d{2}:?\d{2}))?$/i;

/**
 * Parse Dimo's UTC CSV format without Date.parse. Safari does not support the
 * space-separated timestamp emitted by the exporter (for example,
 * `2026-07-11 11:38:08 +0000`).
 */
function parseDate(value: string): number {
  const match = CSV_DATE_PATTERN.exec(value.trim());
  if (!match) return Number.NaN;

  const [, yearValue, monthValue, dayValue, hourValue, minuteValue, secondValue, millisValue, timezoneValue] = match;
  const year = Number(yearValue);
  const month = Number(monthValue);
  const day = Number(dayValue);
  const hour = hourValue === undefined ? 0 : Number(hourValue);
  const minute = minuteValue === undefined ? 0 : Number(minuteValue);
  const second = secondValue === undefined ? 0 : Number(secondValue);
  const millis = millisValue === undefined ? 0 : Number(millisValue.padEnd(3, "0"));

  // Date-only values retain their previous UTC-midnight behavior. Timestamps
  // require an explicit UTC offset so web and iOS interpret them identically.
  if (hourValue !== undefined && timezoneValue === undefined) return Number.NaN;

  const utcTimestamp = Date.UTC(year, month - 1, day, hour, minute, second, millis);
  const utcDate = new Date(utcTimestamp);
  if (
    utcDate.getUTCFullYear() !== year ||
    utcDate.getUTCMonth() !== month - 1 ||
    utcDate.getUTCDate() !== day ||
    utcDate.getUTCHours() !== hour ||
    utcDate.getUTCMinutes() !== minute ||
    utcDate.getUTCSeconds() !== second ||
    utcDate.getUTCMilliseconds() !== millis
  ) {
    return Number.NaN;
  }

  if (!timezoneValue || timezoneValue.toUpperCase() === "Z") return utcTimestamp;

  const sign = timezoneValue[0] === "+" ? 1 : -1;
  const offsetDigits = timezoneValue.slice(1).replace(":", "");
  const offsetHours = Number(offsetDigits.slice(0, 2));
  const offsetMinutes = Number(offsetDigits.slice(2));
  if (offsetHours > 23 || offsetMinutes > 59) return Number.NaN;
  return utcTimestamp - sign * (offsetHours * 60 + offsetMinutes) * 60_000;
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
