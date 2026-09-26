import { isSharedLendContact, type Lend, type LendKind } from "@/lib/types";

/** Which way an unsettled balance runs. */
export type LendDirection = "owedToMe" | "iOwe";

export interface LendContactSummary {
  contactName: string;
  contactId: string;
  /**
   * Signed net balance: positive when the contact owes the user, negative when
   * the user owes the contact.
   */
  balance: number;
  /** Balance without its sign, for display next to a direction label. */
  magnitude: number;
  direction: LendDirection;
  entryCount: number;
  lastOccurredAt: number;
  /** Currency of the newest entry; absent means the display currency. */
  currency?: string;
  /** Ledger shared with another Dimo account. */
  shared: boolean;
}

export interface LendContactSuggestion {
  contactName: string;
  contactId: string;
}

export interface LendDayGroup {
  label: string;
  netAmount: number;
  items: Lend[];
}

/** Both sides of the ledger, netted per contact. */
export interface LendTotals {
  owedToMe: number;
  iOwe: number;
  net: number;
}

/** Money came towards the user rather than away from them. */
export function isIncomingLend(kind: LendKind): boolean {
  return kind === "repaid" || kind === "borrowed";
}

/**
 * Positive for money that left the user's pocket (lent out, or paid back to
 * someone they borrowed from), negative for money that came in.
 */
export function signedLendAmount(lend: Lend): number {
  return isIncomingLend(lend.kind) ? -lend.amount : lend.amount;
}

/** Stands in for an empty comment so a row still says what it was. */
export function lendKindLabel(kind: LendKind): string {
  switch (kind) {
    case "repaid":
      return "Got back";
    case "borrowed":
      return "Borrowed";
    case "returned":
      return "Paid back";
    default:
      return "Money lent";
  }
}

/**
 * Both sides of the ledger. Takes already-netted contact summaries rather than
 * raw entries, so a contact the user has both lent to and borrowed from is not
 * counted on both sides.
 */
export function lendingTotals(summaries: LendContactSummary[]): LendTotals {
  let owedToMe = 0;
  let iOwe = 0;
  for (const summary of summaries) {
    if (summary.direction === "owedToMe") owedToMe += summary.balance;
    else iOwe += summary.magnitude;
  }
  return { owedToMe, iOwe, net: owedToMe - iOwe };
}

/**
 * Active contacts ordered by largest balance in either direction. Only contacts
 * whose balance nets to zero are omitted — a negative balance means the user
 * owes them and must still be listed.
 */
export function lendContactSummaries(lends: Lend[]): LendContactSummary[] {
  const summaries = new Map<string, LendContactSummary>();
  const newestFirst = [...lends].sort((a, b) => b.occurredAt - a.occurredAt);

  for (const lend of newestFirst) {
    const current = summaries.get(lend.contactId);
    if (current) {
      current.balance += signedLendAmount(lend);
      current.entryCount += 1;
      current.lastOccurredAt = Math.max(current.lastOccurredAt, lend.occurredAt);
      continue;
    }
    summaries.set(lend.contactId, {
      contactName: lend.contactName,
      contactId: lend.contactId,
      balance: signedLendAmount(lend),
      magnitude: 0,
      direction: "owedToMe",
      entryCount: 1,
      lastOccurredAt: lend.occurredAt,
      ...(lend.currency ? { currency: lend.currency } : {}),
      shared: isSharedLendContact(lend.contactId),
    });
  }

  return [...summaries.values()]
    .map((summary) => ({
      ...summary,
      magnitude: Math.abs(summary.balance),
      direction: (summary.balance > 0 ? "owedToMe" : "iOwe") as LendDirection,
    }))
    .filter((summary) => summary.magnitude > 0.0001)
    .sort(
      (a, b) =>
        b.magnitude - a.magnitude ||
        a.contactName.localeCompare(b.contactName),
    );
}

/** Newest-first history grouped by the display day label. */
export function groupLendsByDay(lends: Lend[]): LendDayGroup[] {
  const groups = new Map<string, Lend[]>();
  for (const lend of [...lends].sort((a, b) => b.occurredAt - a.occurredAt)) {
    const items = groups.get(lend.day);
    if (items) items.push(lend);
    else groups.set(lend.day, [lend]);
  }
  return [...groups].map(([label, items]) => ({
    label,
    netAmount: items.reduce((total, lend) => total + signedLendAmount(lend), 0),
    items,
  }));
}

/**
 * Signed balance with one contact: positive when they owe the user, negative
 * when the user owes them. When editing an entry, exclude it so its current
 * amount remains eligible.
 */
export function netLendBalance(
  contactId: string,
  lends: Lend[],
  excludingLendId?: string,
): number {
  let total = 0;
  for (const lend of lends) {
    if (lend.contactId !== contactId || lend.id === excludingLendId) continue;
    total += signedLendAmount(lend);
  }
  return total;
}

/**
 * How much a settlement of `kind` may be for without overshooting zero:
 * `repaid` is capped by what the contact owes, `returned` by what the user
 * owes them. Entries that open a balance are uncapped (`null`).
 */
export function settlementLimit(
  kind: LendKind,
  contactId: string,
  lends: Lend[],
  excludingLendId?: string,
): number | null {
  if (kind === "lent" || kind === "borrowed") return null;
  const balance = netLendBalance(contactId, lends, excludingLendId);
  return Math.max(0, kind === "repaid" ? balance : -balance);
}

/** The entry kind that settles a balance running in `direction`. */
export function settlementKind(direction: LendDirection): LendKind {
  return direction === "owedToMe" ? "repaid" : "returned";
}

/**
 * Chronological entries in the contact's current unsettled cycle; everything
 * before the most recent zero balance belongs to a completed settlement.
 */
export function unsettledLends(contactId: string, lends: Lend[]): Lend[] {
  const contactLends = lends
    .filter((lend) => lend.contactId === contactId)
    .sort((a, b) => a.occurredAt - b.occurredAt || a.id.localeCompare(b.id));
  let balance = 0;
  let start = 0;
  contactLends.forEach((lend, index) => {
    balance += signedLendAmount(lend);
    if (Math.abs(balance) < 0.0001) start = index + 1;
  });
  return contactLends.slice(start);
}

/** Most recently used contacts, deduped per person, for one-tap picks. */
export function recentLendContacts(lends: Lend[], limit = 6): LendContactSuggestion[] {
  const seen = new Set<string>();
  const result: LendContactSuggestion[] = [];
  for (const lend of [...lends].sort((a, b) => b.occurredAt - a.occurredAt)) {
    if (seen.has(lend.contactId)) continue;
    seen.add(lend.contactId);
    result.push({ contactName: lend.contactName, contactId: lend.contactId });
    if (result.length === limit) break;
  }
  return result;
}

/** Who recorded or last changed a shared entry, when it was the other person. */
export function lendAttribution(lend: Lend): string | null {
  if (!isSharedLendContact(lend.contactId)) return null;
  const firstName = lend.contactName.split(" ")[0] || lend.contactName;
  if (lend.createdBy === "contact") return `Added by ${firstName}`;
  if (lend.lastEditedBy === "contact") return `Edited by ${firstName}`;
  return null;
}
