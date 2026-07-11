import type { RecurringEntity } from "@/data/model";

const DAY_MS = 86_400_000;

export function localDateKey(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function parseLocalDate(value: string) {
  const [year, month, day] = value.split("-").map(Number);
  return new Date(year, month - 1, day);
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

export function recurringDueLabel(recurring: Pick<RecurringEntity, "anchorDate" | "frequency">, now = new Date()) {
  const due = nextOccurrence(recurring, now);
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const days = Math.round((due.getTime() - today.getTime()) / DAY_MS);
  const date = due.toLocaleDateString(undefined, { month: "short", day: "numeric" });
  const relative = days === 0 ? "today" : days === 1 ? "tomorrow" : `in ${days} days`;
  return `Due ${date} · ${relative}`;
}
