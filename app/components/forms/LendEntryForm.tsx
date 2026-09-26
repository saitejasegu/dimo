"use client";

import { useEffect, useMemo, useState } from "react";
import { localDateKey, localDateTimeTimestamp } from "@/lib/dates";
import { symbolFor } from "@/lib/format";
import type { Lend } from "@/lib/types";
import { useAppActions, useAppState } from "@/store/app-store";
import { sharingErrorText, useLendingSharing, type LendUser } from "@/store/lending-sharing";
import {
  lendFlow,
  lendKindFor,
  netLendBalance,
  recentLendContacts,
  type LendFlow,
} from "@/features/lending/selectors";
import { Avatar } from "@/components/ui/Avatar";
import { Button } from "@/components/ui/Button";
import { Chip } from "@/components/ui/Chip";
import { DateField } from "@/components/ui/DateField";
import { SegmentedControl } from "@/components/ui/SegmentedControl";
import { TextField } from "@/components/ui/TextField";

/** What the lend editor was opened for. */
export type LendEditorTarget =
  /** A new entry, optionally for a known person and with a preset direction. */
  | { mode: "new"; contactId?: string; contactName?: string; flow?: LendFlow }
  | { mode: "edit"; lend: Lend };

const FLOWS = [
  { value: "gave", label: "I gave" },
  { value: "got", label: "I got" },
] satisfies Array<{ value: LendFlow; label: string }>;

export function lendEditorTitle(target: LendEditorTarget) {
  return target.mode === "edit" ? "Edit entry" : "Add entry";
}

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
/** Dimo accounts are searched once this many characters are typed. */
const MIN_SEARCH_LENGTH = 2;

/** Dimo accounts matching a typed query. */
interface DimoSearch {
  query: string;
  users: LendUser[];
}

function relationLabel(user: LendUser) {
  switch (user.relation) {
    case "connected":
      return "Shared";
    case "invited":
      return "Invited";
    case "invitedYou":
      return "Invited you";
    default:
      return "On Dimo";
  }
}

function amountText(amount: number) {
  return Number.isInteger(amount) ? String(amount) : amount.toFixed(2);
}

/**
 * Add or edit a lending entry as "I gave" / "I got". Whether it's a new loan
 * or a repayment follows from the balance with that person, so users never
 * pick between lent, borrowed, got back and paid back.
 */
export function LendEntryForm({
  target,
  onDone,
}: {
  target: LendEditorTarget;
  onDone: () => void;
}) {
  const { lends, currency, weekStart } = useAppState("lends", "currency", "weekStart");
  const { saveLend, showToast } = useAppActions();
  const sharing = useLendingSharing();
  const { connections, outgoingInvites } = sharing;
  const editing = target.mode === "edit" ? target.lend : null;

  const [flow, setFlow] = useState<LendFlow>(() =>
    target.mode === "edit" ? lendFlow(target.lend.kind) : (target.flow ?? "gave"),
  );
  const [contactName, setContactName] = useState(() =>
    target.mode === "edit" ? target.lend.contactName : (target.contactName ?? ""),
  );
  const [contactId, setContactId] = useState<string | null>(() =>
    target.mode === "edit" ? target.lend.contactId : (target.contactId ?? null),
  );
  const [date, setDate] = useState(() =>
    localDateKey(editing ? new Date(editing.occurredAt) : new Date()),
  );
  const [amount, setAmount] = useState(() => (editing ? amountText(editing.amount) : ""));
  const [comment, setComment] = useState(() => editing?.comment ?? "");
  // The Dimo account picked from the search; saving invites them.
  const [dimoUser, setDimoUser] = useState<LendUser | null>(null);
  const [search, setSearch] = useState<DimoSearch | null>(null);

  const contactLocked = target.mode === "edit" || Boolean(target.contactId);
  const query = contactName.trim();
  // Typing (rather than picking someone) searches your people and Dimo.
  const typing = !contactLocked && !contactId && !dimoUser && query.length > 0;
  const searchable = typing && query.length >= MIN_SEARCH_LENGTH;
  const dimoResults = searchable && search?.query === query ? search.users : null;

  useEffect(() => {
    if (!searchable) return;
    let cancelled = false;
    const timer = setTimeout(() => {
      sharing
        .searchUsers(query)
        .then((users) => {
          if (!cancelled) setSearch({ query, users });
        })
        .catch(() => undefined);
    }, 250);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [searchable, query, sharing]);

  function pickDimoUser(user: LendUser) {
    if (user.relation === "invitedYou") {
      showToast(`${user.name} already invited you. Accept their invite in Lending first.`);
      return;
    }
    setDimoUser(user);
    setContactName(user.name);
    // Reuse the shared ledger or the contact a pending invite is for.
    setContactId(user.contactId ?? null);
  }

  const suggestions = useMemo(() => {
    const recent = recentLendContacts(lends, 8);
    for (const connection of connections) {
      if (connection.status !== "active") continue;
      if (!recent.some((suggestion) => suggestion.contactId === connection.contactId)) {
        recent.push({ contactName: connection.contactName, contactId: connection.contactId });
      }
    }
    // Someone invited before any entries were recorded with them.
    for (const invite of outgoingInvites) {
      const { contactId } = invite;
      if (contactId && !recent.some((suggestion) => suggestion.contactId === contactId)) {
        recent.push({ contactName: invite.contactName, contactId });
      }
    }
    return recent;
  }, [lends, connections, outgoingInvites]);

  // Everyone you've recorded, for matching what's typed.
  const knownContacts = useMemo(() => {
    const all = recentLendContacts(lends, Number.MAX_SAFE_INTEGER);
    for (const suggestion of suggestions) {
      if (!all.some((contact) => contact.contactId === suggestion.contactId)) all.push(suggestion);
    }
    return all;
  }, [lends, suggestions]);
  const matchingContacts = useMemo(() => {
    if (!typing) return [];
    const needle = query.toLowerCase();
    // A Dimo result already stands for the contact it's shared or invited as.
    const linked = new Set((dimoResults ?? []).map((user) => user.contactId));
    return knownContacts
      .filter((contact) => contact.contactName.toLowerCase().includes(needle))
      .filter((contact) => !linked.has(contact.contactId))
      .slice(0, 5);
  }, [typing, query, knownContacts, dimoResults]);

  const parsed = Number(amount);
  const canSave = contactName.trim().length > 0 && parsed > 0;
  const symbol = symbolFor(editing?.currency ?? currency);
  const shared = contactId ? Boolean(sharing.activeConnection(contactId)) : false;
  // Balance with this person before this entry: positive when they owe you.
  const balance = contactId ? netLendBalance(contactId, lends, editing?.id) : 0;
  const balanceText =
    Math.abs(balance) < 0.0001
      ? null
      : balance > 0
        ? `${contactName.trim() || "They"} owes you ${symbol}${amountText(balance)}`
        : `You owe ${contactName.trim() || "them"} ${symbol}${amountText(-balance)}`;

  function save() {
    if (!canSave) return;
    // Past days pin to noon like native; today keeps the current time so
    // entries order naturally. An edit on the same day keeps its time.
    const today = localDateKey(new Date());
    const occurredAt =
      editing && localDateKey(new Date(editing.occurredAt)) === date
        ? editing.occurredAt
        : date === today
          ? Date.now()
          : localDateTimeTimestamp(date, "12:00");
    // A newly typed name starts a new person; ids are opaque.
    const savedContactId = contactId ?? `contact_${crypto.randomUUID()}`;
    const saved = saveLend({
      ...(editing ? { id: editing.id } : {}),
      contactId: savedContactId,
      contactName,
      kind: lendKindFor(flow, parsed, balance),
      amount: parsed,
      occurredAt,
      comment,
    });
    if (!saved) return;
    // The entry stays private until they accept; accepting shares it.
    if (dimoUser?.relation === "none") {
      const name = contactName.trim() || dimoUser.name;
      sharing
        .sendInvite({ userId: dimoUser.userId, contactId: savedContactId, contactName: name })
        .then(() => showToast(`Invite sent to ${name}`))
        .catch((cause) => showToast(`Saved, but the invite failed: ${sharingErrorText(cause)}`));
    }
    onDone();
  }

  return (
    <div className="flex flex-col gap-4">
      <SegmentedControl options={FLOWS} value={flow} onChange={setFlow} />

      <div>
        <span className="mb-1.5 block text-xs text-muted">{flow === "gave" ? "To" : "From"}</span>
        {contactLocked ? (
          <div className="rounded-xl border border-line bg-canvas px-3.5 py-[11px] text-base text-ink">
            {contactName}
          </div>
        ) : (
          <>
            <input
              type="text"
              value={contactName}
              onChange={(event) => {
                setContactName(event.target.value);
                setContactId(null);
                setDimoUser(null);
              }}
              placeholder="Their name or Dimo email"
              className="w-full rounded-xl border border-line bg-canvas px-3.5 py-[11px] text-base text-ink outline-none placeholder:text-faint"
            />
            {typing && (matchingContacts.length > 0 || dimoResults !== null) ? (
              <div className="mt-2 overflow-hidden rounded-xl border border-line bg-surface">
                {matchingContacts.map((contact) => (
                  <button
                    type="button"
                    key={contact.contactId}
                    onClick={() => {
                      setContactName(contact.contactName);
                      setContactId(contact.contactId);
                    }}
                    className="flex w-full items-center gap-3 border-b border-line-soft px-3 py-2.5 text-left last:border-b-0 hover:bg-canvas"
                  >
                    <Avatar
                      initial={contact.contactName.charAt(0).toUpperCase()}
                      src={sharing.photoFor(contact.contactId)}
                      size={32}
                      radius={10}
                      textClassName="text-xs"
                    />
                    <span className="min-w-0 flex-1 truncate text-sm font-medium text-ink">
                      {contact.contactName}
                    </span>
                    <span className="shrink-0 text-xs text-muted">
                      {sharing.activeConnection(contact.contactId) ? "Shared" : "Your contact"}
                    </span>
                  </button>
                ))}
                {(dimoResults ?? []).map((user) => (
                  <button
                    type="button"
                    key={user.userId}
                    onClick={() => pickDimoUser(user)}
                    className="flex w-full items-center gap-3 border-b border-line-soft px-3 py-2.5 text-left last:border-b-0 hover:bg-canvas"
                  >
                    <Avatar
                      initial={user.name.charAt(0).toUpperCase()}
                      src={user.photoUrl}
                      size={32}
                      radius={10}
                      textClassName="text-xs"
                    />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-sm font-medium text-ink">
                        {user.name}
                      </span>
                      {user.email ? (
                        <span className="block truncate text-xs text-muted">{user.email}</span>
                      ) : null}
                    </span>
                    <span className="shrink-0 text-xs font-medium text-green">
                      {relationLabel(user)}
                    </span>
                  </button>
                ))}
                {dimoResults !== null && dimoResults.length === 0 && matchingContacts.length === 0 ? (
                  <p className="px-3 py-2.5 text-xs text-muted">
                    {EMAIL_PATTERN.test(query)
                      ? "No Dimo account uses this email."
                      : `No one named “${query}” yet. Saving adds them as a new person.`}
                  </p>
                ) : null}
              </div>
            ) : null}
            {suggestions.length > 0 && query.length === 0 ? (
              <div className="mt-2 flex gap-2 overflow-x-auto pb-1">
                {suggestions.map((suggestion) => (
                  <Chip
                    key={suggestion.contactId}
                    label={suggestion.contactName}
                    surface="canvas"
                    selected={contactId === suggestion.contactId}
                    onClick={() => {
                      setContactName(suggestion.contactName);
                      setContactId(suggestion.contactId);
                    }}
                  />
                ))}
              </div>
            ) : null}
          </>
        )}
        {shared ? (
          <p className="mt-1.5 text-xs text-green">
            Shared with {contactName} — they see this entry too.
          </p>
        ) : dimoUser ? (
          <p className="mt-1.5 text-xs text-muted">
            {dimoUser.relation === "invited"
              ? `Invited ${dimoUser.email ?? dimoUser.name}. This entry is shared once they accept.`
              : `Saving invites ${dimoUser.email ?? dimoUser.name}. This entry stays private until they accept.`}
          </p>
        ) : null}
      </div>

      <DateField
        label="Date"
        value={date}
        onChange={setDate}
        max={localDateKey(new Date())}
        weekStartsOn={weekStart === "Sun" ? 0 : 1}
      />

      <label className="block">
        <span className="mb-1.5 block text-xs text-muted">Amount</span>
        <div className="flex items-center gap-2 rounded-xl border border-line bg-canvas px-3.5 py-[11px]">
          <span className="text-muted">{symbol}</span>
          <input
            type="text"
            inputMode="decimal"
            value={amount}
            onChange={(event) => setAmount(event.target.value.replace(/[^0-9.]/g, ""))}
            placeholder="0"
            className="min-w-0 flex-1 bg-transparent text-base text-ink outline-none placeholder:text-faint"
          />
        </div>
        {balanceText ? (
          <span className="mt-1.5 block text-xs text-faint">{balanceText}</span>
        ) : null}
      </label>

      <TextField
        label="Note (optional)"
        value={comment}
        onChange={setComment}
        placeholder="e.g. Dinner, cab fare"
      />

      <Button enabled={canSave} fullWidth onClick={save}>
        Save
      </Button>
    </div>
  );
}

