import type { RecurringEntity } from "@/data/model";

const DAY_MS = 86_400_000;

export function localDateKey(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function localTimeKey(date: Date) {
  const hours = String(date.getHours()).padStart(2, "0");
  const minutes = String(date.getMinutes()).padStart(2, "0");
  return `${hours}:${minutes}`;
}

export function parseLocalDate(value: string) {
  const [year, month, day] = value.split("-").map(Number);
  return new Date(year, month - 1, day);
}

/**
 * Combine local `YYYY-MM-DD` + `HH:mm` into epoch ms.
 * Missing/invalid date falls back to now; result is capped at now.
 */
export function localDateTimeTimestamp(
  dateKey: string,
  timeKey: string,
  now = new Date(),
): number {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateKey)) return now.getTime();
  const timeMatch = /^(\d{2}):(\d{2})$/.exec(timeKey);
  const hours = timeMatch ? Number(timeMatch[1]) : now.getHours();
  const minutes = timeMatch ? Number(timeMatch[2]) : now.getMinutes();
  const [year, month, day] = dateKey.split("-").map(Number);
  const ts = new Date(year, month - 1, day, hours, minutes, 0, 0).getTime();
  return Math.min(ts, now.getTime());
}

export function formatTransactionDay(timestamp: number, now = new Date()) {
  const date = new Date(timestamp);
  const today = localDateKey(now);
  const key = localDateKey(date);
  if (key === today) return "Today";
  const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
  if (key === localDateKey(yesterday)) return "Yesterday";
  return date.toLocaleDateString(undefined, {
    weekday: "long",
    month: "short",
    day: "numeric",
    year: date.getFullYear() === now.getFullYear() ? undefined : "numeric",
  });
}

export function formatTransactionTime(timestamp: number) {
  return new Date(timestamp).toLocaleTimeString(undefined, {
    hour: "numeric",
    minute: "2-digit",
  });
}

function daysInMonth(year: number, monthIndex: number) {
  return new Date(year, monthIndex + 1, 0).getDate();
}

export function nextOccurrence(recurring: Pick<RecurringEntity, "anchorDate" | "frequency">, now = new Date()) {
  const anchor = parseLocalDate(recurring.anchorDate);
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  if (anchor >= today) return anchor;

  if (recurring.frequency === "monthly") {
    const candidateFor = (year: number, month: number) =>
      new Date(year, month, Math.min(anchor.getDate(), daysInMonth(year, month)));
    let candidate = candidateFor(today.getFullYear(), today.getMonth());
    if (candidate < today) candidate = candidateFor(today.getFullYear(), today.getMonth() + 1);
    return candidate;
  }

  const candidateFor = (year: number) =>
    new Date(
      year,
      anchor.getMonth(),
      Math.min(anchor.getDate(), daysInMonth(year, anchor.getMonth())),
    );
  let candidate = candidateFor(today.getFullYear());
  if (candidate < today) candidate = candidateFor(today.getFullYear() + 1);
  return candidate;
}

/**
 * Every occurrence from the anchor/start date through today (inclusive).
 * Future start dates return an empty list.
 */
export function occurrencesThrough(
  recurring: Pick<RecurringEntity, "anchorDate" | "frequency">,
  now = new Date(),
): Date[] {
  const anchor = parseLocalDate(recurring.anchorDate);
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  if (anchor > today) return [];

  const dates: Date[] = [];
  const day = anchor.getDate();

  if (recurring.frequency === "monthly") {
    let year = anchor.getFullYear();
    let month = anchor.getMonth();
    while (dates.length < 1200) {
      const date = new Date(year, month, Math.min(day, daysInMonth(year, month)));
      if (date > today) break;
      dates.push(date);
      month += 1;
      if (month > 11) {
        month = 0;
        year += 1;
      }
    }
    return dates;
  }

  let year = anchor.getFullYear();
  const month = anchor.getMonth();
  while (dates.length < 200) {
    const date = new Date(year, month, Math.min(day, daysInMonth(year, month)));
    if (date > today) break;
    dates.push(date);
    year += 1;
  }
  return dates;
}

export type RecurringOccurrenceSelection = "all" | "selected";

/** Transaction dates to create when saving a recurring schedule. */
export function recurringTransactionDates(
  recurring: Pick<RecurringEntity, "anchorDate" | "frequency">,
  selection: RecurringOccurrenceSelection,
  now = new Date(),
): Date[] {
  const anchor = parseLocalDate(recurring.anchorDate);
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  if (anchor > today) return [];
  return selection === "all" ? occurrencesThrough(recurring, now) : [anchor];
}

export function occurrenceTimestamp(date: Date, timeKey?: string, now = new Date()) {
  if (timeKey) return localDateTimeTimestamp(localDateKey(date), timeKey, now);
  return new Date(
    date.getFullYear(),
    date.getMonth(),
    date.getDate(),
    12,
    0,
    0,
  ).getTime();
}

export function recurringDueLabel(recurring: Pick<RecurringEntity, "anchorDate" | "frequency">, now = new Date()) {
  const due = nextOccurrence(recurring, now);
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const days = Math.round((due.getTime() - today.getTime()) / DAY_MS);
  const date = due.toLocaleDateString(undefined, { month: "short", day: "numeric" });
  const relative = days === 0 ? "today" : days === 1 ? "tomorrow" : `in ${days} days`;
  return `Due ${date} · ${relative}`;
}
