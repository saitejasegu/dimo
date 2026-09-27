"use client";

import { useMemo, useState } from "react";
import { money } from "@/lib/format";
import { toMajorUnits, toMinorUnits } from "@/features/currency/rates";
import { splitShares, type SplitMode, type SplitShares } from "@/features/transactions/split";
import type { LendUser } from "@/store/lending-sharing";
import { LendPeopleResults, useLendPeople } from "@/components/forms/LendPeopleSearch";
import { Button } from "@/components/ui/Button";
import { Chip } from "@/components/ui/Chip";
import { ChevronIcon } from "@/components/ui/icons";

export interface SplitPersonDraft {
  contactId: string;
  contactName: string;
  /** What's typed for an `exact` or `percent` split. */
  value: string;
  /** Picked from Dimo search without a shared ledger yet; saving invites them. */
  invite?: LendUser;
}

export interface SplitDraft {
  mode: SplitMode;
  /** `null` when the user paid. */
  paidBy: string | null;
  people: SplitPersonDraft[];
}

export const EMPTY_SPLIT: SplitDraft = { mode: "equal", paidBy: null, people: [] };

const MODES = [
  { value: "equal", label: "Equally" },
  { value: "exact", label: "By amount" },
  { value: "percent", label: "By percent" },
] satisfies Array<{ value: SplitMode; label: string }>;

/** One line describing a split, for the expense form. */
export function splitSummary(draft: SplitDraft) {
  const names = draft.people.map((person) => person.contactName.split(" ")[0]);
  const payer = draft.people.find((person) => person.contactId === draft.paidBy);
  const mode = MODES.find((option) => option.value === draft.mode)?.label.toLowerCase();
  return {
    title: `Split with ${names.join(", ")}`,
    detail: `${payer ? `${payer.contactName.split(" ")[0]} paid` : "You paid"} · ${mode}`,
  };
}

const SELECT_CLASS =
  "w-full appearance-none rounded-xl border border-line bg-surface py-2 pl-3 pr-8 text-sm font-medium text-ink outline-none focus-visible:ring-2 focus-visible:ring-green/25";

function SplitSelect({
  label,
  value,
  onChange,
  options,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  options: Array<{ value: string; label: string }>;
}) {
  return (
    <div className="relative min-w-0 flex-1">
      <select
        value={value}
        onChange={(event) => onChange(event.target.value)}
        aria-label={label}
        className={SELECT_CLASS}
      >
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
      <span aria-hidden className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-xs text-muted">
        ▾
      </span>
    </div>
  );
}

function cleanValue(value: string) {
  const cleaned = value.replace(/[^0-9.]/g, "");
  const [whole = "", ...decimal] = cleaned.split(".");
  return decimal.length ? `${whole.slice(0, 7)}.${decimal.join("").slice(0, 2)}` : whole.slice(0, 7);
}

/** Shares in minor units of `currency`, or `null` when the split doesn't add up. */
export function draftShares(draft: SplitDraft, totalMinor: number, currency: string): SplitShares | null {
  return splitShares(
    totalMinor,
    draft.mode,
    draft.people.map((person) => {
      const typed = Number(person.value || 0);
      return {
        contactId: person.contactId,
        value: draft.mode === "exact" ? toMinorUnits(typed, currency) : typed,
      };
    }),
  );
}

/**
 * Whether saving `draft` records anything: someone else paying needs the user
 * to have a share, and the user paying needs someone else to owe part of it.
 */
export function splitIsSavable(draft: SplitDraft, shares: SplitShares | null) {
  if (!shares || draft.people.length === 0) return false;
  return draft.paidBy ? shares.mine > 0 : shares.others.some((other) => other.share > 0);
}

/**
 * The split step of the expense form: who shares the bill, who paid it and
 * how it divides. The expense itself records only the user's share; the rest
 * becomes lending entries.
 */
export function SplitSection({
  draft,
  onChange,
  totalMinor,
  currency,
  onDone,
}: {
  draft: SplitDraft;
  onChange: (draft: SplitDraft) => void;
  totalMinor: number;
  currency: string;
  onDone: () => void;
}) {
  const { suggestions, knownContacts } = useLendPeople();
  const [query, setQuery] = useState("");
  const typed = query.trim();
  const picked = useMemo(
    () => new Set(draft.people.map((person) => person.contactId)),
    [draft.people],
  );
  const shares = totalMinor > 0 ? draftShares(draft, totalMinor, currency) : null;
  const shareOf = (contactId: string | null) =>
    contactId === null
      ? shares?.mine
      : shares?.others.find((other) => other.contactId === contactId)?.share;
  const format = (minor: number | undefined) =>
    minor === undefined ? "—" : money(toMajorUnits(minor, currency), currency);

  function addPerson(person: Omit<SplitPersonDraft, "value">) {
    setQuery("");
    if (picked.has(person.contactId)) return;
    onChange({ ...draft, people: [...draft.people, { ...person, value: "" }] });
  }

  function addTyped() {
    if (!typed) return;
    const known = knownContacts.find(
      (contact) => contact.contactName.toLowerCase() === typed.toLowerCase(),
    );
    // A new name starts a new person; ids are opaque.
    addPerson(known ?? { contactId: `contact_${crypto.randomUUID()}`, contactName: typed });
  }

  function removePerson(contactId: string) {
    onChange({
      ...draft,
      paidBy: draft.paidBy === contactId ? null : draft.paidBy,
      people: draft.people.filter((person) => person.contactId !== contactId),
    });
  }

  function setValue(contactId: string, value: string) {
    onChange({
      ...draft,
      people: draft.people.map((person) =>
        person.contactId === contactId ? { ...person, value: cleanValue(value) } : person,
      ),
    });
  }

  const payer = draft.people.find((person) => person.contactId === draft.paidBy);
  const unpicked = suggestions.filter((suggestion) => !picked.has(suggestion.contactId));
  const hasPeople = draft.people.length > 0;
  const savable = splitIsSavable(draft, shares);

  let problem: string | null = null;
  if (hasPeople && totalMinor > 0 && !savable) {
    if (!shares) {
      problem = draft.mode === "percent"
        ? "Shares add up to more than 100%."
        : `Shares add up to more than ${format(totalMinor)}.`;
    } else {
      problem = payer ? "Your share is zero — nothing to record." : "Nobody else has a share yet.";
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center gap-2">
        <button
          type="button"
          onClick={onDone}
          aria-label="Back to expense"
          className="-ml-1.5 flex h-9 w-9 items-center justify-center rounded-full text-ink hover:bg-canvas"
        >
          <ChevronIcon direction="left" />
        </button>
        <p className="font-display text-base font-semibold text-ink">
          Split {totalMinor > 0 ? format(totalMinor) : "expense"}
        </p>
      </div>

      <div>
        <input
          type="text"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          onKeyDown={(event) => {
            if (event.key !== "Enter") return;
            event.preventDefault();
            addTyped();
          }}
          placeholder="Add a name or Dimo email"
          aria-label="Add a person to split with"
          autoFocus={!hasPeople}
          className="w-full rounded-xl border border-line bg-canvas px-3.5 py-[11px] text-base text-ink outline-none placeholder:text-faint"
        />
        {typed ? (
          <>
            <LendPeopleResults
              query={typed}
              knownContacts={knownContacts}
              excludeContactIds={picked}
              onPickContact={addPerson}
              onPickUser={(user) =>
                addPerson({
                  // Reuse the shared ledger or the contact a pending invite is for.
                  contactId: user.contactId ?? `contact_${crypto.randomUUID()}`,
                  contactName: user.name,
                  ...(user.relation === "none" ? { invite: user } : {}),
                })
              }
            />
            <button
              type="button"
              onClick={addTyped}
              className="mt-2 text-xs font-medium text-green"
            >
              Add “{typed}”
            </button>
          </>
        ) : unpicked.length > 0 ? (
          <div className="mt-2 flex gap-2 overflow-x-auto pb-1">
            {unpicked.map((suggestion) => (
              <Chip
                key={suggestion.contactId}
                label={suggestion.contactName}
                surface="canvas"
                onClick={() => addPerson(suggestion)}
              />
            ))}
          </div>
        ) : null}
      </div>

      {hasPeople ? (
        <>
          <div className="flex gap-2">
            <SplitSelect
              label="Paid by"
              value={draft.paidBy ?? ""}
              onChange={(paidBy) => onChange({ ...draft, paidBy: paidBy || null })}
              options={[
                { value: "", label: "You paid" },
                ...draft.people.map((person) => ({
                  value: person.contactId,
                  label: `${person.contactName} paid`,
                })),
              ]}
            />
            <SplitSelect
              label="How to split"
              value={draft.mode}
              onChange={(mode) => onChange({ ...draft, mode: mode as SplitMode })}
              options={MODES}
            />
          </div>

          <div className="overflow-hidden rounded-xl border border-line bg-surface">
            <div className="flex min-h-11 items-center gap-2 border-b border-line-soft py-1.5 pl-3.5 pr-1.5">
              <span className="min-w-0 flex-1 text-sm font-medium text-ink">You</span>
              <span className="text-sm text-muted">{format(shareOf(null))}</span>
              {/* Lines up with the remove buttons on everyone else's rows. */}
              <span aria-hidden className="w-8 shrink-0" />
            </div>
            {draft.people.map((person) => (
              <div
                key={person.contactId}
                className="flex min-h-11 items-center gap-2 border-b border-line-soft py-1.5 pl-3.5 pr-1.5 last:border-b-0"
              >
                <span className="min-w-0 flex-1 truncate text-sm font-medium text-ink">
                  {person.contactName}
                </span>
                {draft.mode === "equal" ? (
                  <span className="text-sm text-muted">{format(shareOf(person.contactId))}</span>
                ) : (
                  <label className="flex w-24 items-center gap-1 rounded-lg border border-line bg-canvas px-2.5 py-1.5">
                    <input
                      type="text"
                      inputMode="decimal"
                      value={person.value}
                      onChange={(event) => setValue(person.contactId, event.target.value)}
                      placeholder="0"
                      aria-label={`${person.contactName}'s ${draft.mode === "percent" ? "percentage" : "amount"}`}
                      className="min-w-0 flex-1 bg-transparent text-right text-sm text-ink outline-none placeholder:text-faint"
                    />
                    {draft.mode === "percent" ? <span className="text-xs text-muted">%</span> : null}
                  </label>
                )}
                <button
                  type="button"
                  aria-label={`Remove ${person.contactName}`}
                  onClick={() => removePerson(person.contactId)}
                  className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-xs text-faint hover:bg-canvas hover:text-ink"
                >
                  ✕
                </button>
              </div>
            ))}
          </div>

          {problem ? (
            <p className="text-xs text-danger">{problem}</p>
          ) : payer && shares ? (
            <p className="text-xs text-muted">
              You owe {payer.contactName} {format(shares.mine)}. Only your share counts as spending.
            </p>
          ) : (
            <p className="text-xs text-muted">Only your share counts as spending. The rest goes to Lending.</p>
          )}
        </>
      ) : null}

      <Button
        fullWidth
        variant={hasPeople ? "primary" : "secondary"}
        enabled={!hasPeople || savable || totalMinor === 0}
        onClick={onDone}
      >
        {hasPeople ? "Done" : "Cancel"}
      </Button>
    </div>
  );
}
