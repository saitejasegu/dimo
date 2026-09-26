"use client";

import { useEffect, useMemo, useState } from "react";
import { cn } from "@/lib/cn";
import { localDateKey, localDateTimeTimestamp } from "@/lib/dates";
import { symbolFor } from "@/lib/format";
import { isSharedLendContact, type Lend, type LendKind } from "@/lib/types";
import { useAppActions, useAppState } from "@/store/app-store";
import { useLendingSharing, type LendUser } from "@/store/lending-sharing";
import { errorText } from "@/components/forms/LedgerSharingForms";
import {
  recentLendContacts,
  settlementKind,
  settlementLimit,
  type LendDirection,
} from "@/features/lending/selectors";
import { Avatar } from "@/components/ui/Avatar";
import { Button } from "@/components/ui/Button";
import { Chip } from "@/components/ui/Chip";
import { DateField } from "@/components/ui/DateField";
import { SegmentedControl } from "@/components/ui/SegmentedControl";
import { TextField } from "@/components/ui/TextField";

/** What the lend editor was opened for. */
export type LendEditorTarget =
  | { mode: "new" }
  /** Settle a contact's balance from its summary row. */
  | { mode: "settle"; contactId: string; contactName: string; direction: LendDirection }
  | { mode: "edit"; lend: Lend };

const DIRECTIONS = [
  { value: "lent", label: "I lent" },
  { value: "borrowed", label: "I borrowed" },
] satisfies Array<{ value: LendKind; label: string }>;

const TITLES: Record<LendKind, { add: string; edit: string; save: string; editSave: string }> = {
  lent: { add: "Add lend", edit: "Edit lend", save: "Save lend", editSave: "Save lend" },
  borrowed: {
    add: "Add borrowing",
    edit: "Edit borrowing",
    save: "Save borrowing",
    editSave: "Save borrowing",
  },
  repaid: { add: "Got back", edit: "Edit repayment", save: "Save got back", editSave: "Save repayment" },
  returned: { add: "Paid back", edit: "Edit payment", save: "Save paid back", editSave: "Save payment" },
};

const CONTACT_LABELS: Record<LendKind, string> = {
  lent: "Lent to",
  borrowed: "Borrowed from",
  repaid: "From",
  returned: "To",
};

const AMOUNT_LABELS: Record<LendKind, string> = {
  lent: "Amount",
  borrowed: "Amount",
  repaid: "Amount got back",
  returned: "Amount paid back",
};

const COMMENT_PLACEHOLDERS: Record<LendKind, string> = {
  lent: "e.g. Dinner split, emergency",
  borrowed: "e.g. Rent top-up, cab fare",
  repaid: "e.g. Partial repayment",
  returned: "e.g. Partial payment",
};

export function lendEditorTitle(target: LendEditorTarget) {
  if (target.mode === "edit") return TITLES[target.lend.kind].edit;
  if (target.mode === "settle") return TITLES[settlementKind(target.direction)].add;
  return "Add lending entry";
}

function initialKind(target: LendEditorTarget): LendKind {
  if (target.mode === "edit") return target.lend.kind;
  if (target.mode === "settle") return settlementKind(target.direction);
  return "lent";
}

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** A typed email looked up against Dimo accounts; `user` is null when none matched. */
interface DimoLookup {
  email: string;
  user: LendUser | null;
}

function dimoUserNote(user: LendUser) {
  switch (user.relation) {
    case "self":
      return "That’s your own account.";
    case "invitedYou":
      return `${user.name} already invited you. Accept their invite in Lending first.`;
    default:
      return null;
  }
}

function amountText(amount: number) {
  return Number.isInteger(amount) ? String(amount) : amount.toFixed(2);
}

/**
 * Add, settle or edit a lending entry. Web counterpart of the native lend
 * sheets: settlements are capped at the balance they close, editing never
 * flips direction, and a shared ledger's contact is chosen from its chip.
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

  const [kind, setKind] = useState<LendKind>(() => initialKind(target));
  const [contactName, setContactName] = useState(() =>
    target.mode === "new" ? "" : target.mode === "edit" ? target.lend.contactName : target.contactName,
  );
  const [contactId, setContactId] = useState<string | null>(() =>
    target.mode === "new" ? null : target.mode === "edit" ? target.lend.contactId : target.contactId,
  );
  const [date, setDate] = useState(() =>
    localDateKey(editing ? new Date(editing.occurredAt) : new Date()),
  );
  const [amount, setAmount] = useState(() => (editing ? amountText(editing.amount) : ""));
  const [comment, setComment] = useState(() => editing?.comment ?? "");
  // The Dimo account picked from an email lookup; saving invites them.
  const [dimoUser, setDimoUser] = useState<LendUser | null>(null);
  const [lookup, setLookup] = useState<DimoLookup | null>(null);

  const settling = kind === "repaid" || kind === "returned";
  const contactLocked = target.mode !== "new";
  const typedEmail = contactName.trim().toLowerCase();
  const searchable =
    !contactLocked && !dimoUser && sharing.sharingAvailable && EMAIL_PATTERN.test(typedEmail);
  const currentLookup = searchable && lookup?.email === typedEmail ? lookup : null;

  // Typing an email looks for the Dimo account that uses it.
  useEffect(() => {
    if (!searchable) return;
    let cancelled = false;
    const timer = setTimeout(() => {
      sharing
        .findUser(typedEmail)
        .then((user) => {
          if (!cancelled) setLookup({ email: typedEmail, user });
        })
        .catch(() => undefined);
    }, 350);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [searchable, typedEmail, sharing]);

  function pickDimoUser(user: LendUser) {
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

  const limit = contactId
    ? settlementLimit(kind, contactId, lends, editing?.id)
    : settling
      ? 0
      : null;
  const parsed = Number(amount);
  const tooMuch = limit !== null && parsed > limit + 0.000_001;
  const canSave = contactName.trim().length > 0 && parsed > 0 && !tooMuch;
  const symbol = symbolFor(editing?.currency ?? currency);
  const shared = contactId ? isSharedLendContact(contactId) : false;

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
      kind,
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
        .catch((cause) => showToast(`Saved, but the invite failed: ${errorText(cause)}`));
    }
    onDone();
  }

  return (
    <div className="flex flex-col gap-4">
      {target.mode === "new" ? (
        <SegmentedControl options={DIRECTIONS} value={kind} onChange={setKind} />
      ) : null}

      <div>
        <span className="mb-1.5 block text-xs text-muted">{CONTACT_LABELS[kind]}</span>
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
            {currentLookup?.user && !dimoUserNote(currentLookup.user) ? (
              <button
                type="button"
                onClick={() => currentLookup.user && pickDimoUser(currentLookup.user)}
                className="mt-2 flex w-full items-center gap-3 rounded-xl border border-green/50 bg-surface px-3 py-2.5 text-left"
              >
                <Avatar
                  initial={currentLookup.user.name.charAt(0).toUpperCase()}
                  size={32}
                  radius={10}
                  textClassName="text-xs"
                />
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-sm font-medium text-ink">
                    {currentLookup.user.name}
                  </span>
                  <span className="block truncate text-xs text-muted">
                    {currentLookup.user.email}
                  </span>
                </span>
                <span className="shrink-0 text-xs font-medium text-green">
                  {currentLookup.user.relation === "connected"
                    ? "Shared"
                    : currentLookup.user.relation === "invited"
                      ? "Invited"
                      : "On Dimo"}
                </span>
              </button>
            ) : null}
            {currentLookup?.user && dimoUserNote(currentLookup.user) ? (
              <p className="mt-1.5 text-xs text-muted">{dimoUserNote(currentLookup.user)}</p>
            ) : null}
            {currentLookup && !currentLookup.user ? (
              <p className="mt-1.5 text-xs text-muted">No Dimo account uses this email.</p>
            ) : null}
            {suggestions.length > 0 && !searchable && !dimoUser ? (
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
            Shared ledger — {contactName} sees this entry too.
          </p>
        ) : dimoUser ? (
          <p className="mt-1.5 text-xs text-muted">
            {dimoUser.relation === "invited"
              ? `Invited ${dimoUser.email}. This entry is shared once they accept.`
              : `Saving invites ${dimoUser.email}. This entry stays private until they accept.`}
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
        <span className="mb-1.5 block text-xs text-muted">{AMOUNT_LABELS[kind]}</span>
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
        {limit !== null ? (
          <span className={cn("mt-1.5 block text-xs", tooMuch ? "text-danger" : "text-faint")}>
            {limit > 0 ? `Up to ${symbol}${amountText(limit)} outstanding` : "Nothing outstanding"}
          </span>
        ) : null}
      </label>

      <TextField
        label="Comments (optional)"
        value={comment}
        onChange={setComment}
        placeholder={COMMENT_PLACEHOLDERS[kind]}
      />

      <Button enabled={canSave} fullWidth onClick={save}>
        {editing ? TITLES[kind].editSave : TITLES[kind].save}
      </Button>
    </div>
  );
}

