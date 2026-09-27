/**
 * Splitting one expense between the user and other people. All amounts are
 * integer minor units of the currency the expense was entered in; the user's
 * share is whatever is left, so shares always add up to the total exactly.
 */

export type SplitMode = "equal" | "exact" | "percent";

export interface SplitShareInput {
  contactId: string;
  /** Minor units for `exact`, a percentage for `percent`; ignored for `equal`. */
  value: number;
}

export interface SplitShares {
  /** The user's own share, recorded as the expense. */
  mine: number;
  others: Array<{ contactId: string; share: number }>;
}

/**
 * Shares of `totalMinor` for the user and each person, or `null` when the
 * split doesn't add up (more than the total, over 100%, or nobody to split
 * with). An equal split gives any leftover minor units to the user first.
 */
export function splitShares(
  totalMinor: number,
  mode: SplitMode,
  people: SplitShareInput[],
): SplitShares | null {
  if (!(totalMinor > 0) || people.length === 0) return null;

  if (mode === "equal") {
    const count = people.length + 1;
    const base = Math.floor(totalMinor / count);
    const remainder = totalMinor - base * count;
    return {
      mine: base + (remainder > 0 ? 1 : 0),
      others: people.map((person, index) => ({
        contactId: person.contactId,
        share: base + (index + 1 < remainder ? 1 : 0),
      })),
    };
  }

  if (people.some((person) => !(person.value >= 0))) return null;
  if (mode === "percent") {
    const percent = people.reduce((sum, person) => sum + person.value, 0);
    if (percent > 100 + 1e-9) return null;
  }
  const others = people.map((person) => ({
    contactId: person.contactId,
    // Rounding down leaves any fraction of a minor unit with the user.
    share:
      mode === "exact"
        ? Math.round(person.value)
        : Math.floor((totalMinor * person.value) / 100 + 1e-9),
  }));
  const mine = totalMinor - others.reduce((sum, other) => sum + other.share, 0);
  return mine < 0 ? null : { mine, others };
}
