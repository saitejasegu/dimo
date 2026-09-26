"use client";

import { useEffect, useMemo, useState } from "react";
import { cn } from "@/lib/cn";
import { money } from "@/lib/format";
import { isSharedLendContact } from "@/lib/types";
import { useAppActions, useAppState } from "@/store/app-store";
import {
  sharingErrorText,
  useLendingSharing,
  type LendUser,
  type OutgoingLendInvite,
} from "@/store/lending-sharing";
import {
  allLendContactSummaries,
  lendAttribution,
  lendFlow,
  type LendContactSummary,
  type LendFlow,
} from "@/features/lending/selectors";
import type { LendEditorTarget } from "@/components/forms/LendEntryForm";
import { Frame, type Variant } from "@/components/common/LendingDialogs";
import { CancelInviteDialog, IncomingInviteCard } from "@/components/common/LendingInvites";
import { Avatar } from "@/components/ui/Avatar";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { TextField } from "@/components/ui/TextField";

/** A person on the Lending screen: anyone recorded, or invited before any entries. */
interface LendPerson {
  contactId: string;
  contactName: string;
  /** Positive when they owe you. */
  balance: number;
  currency?: string;
  lastOccurredAt: number;
  entryCount: number;
  /** Currently shared with their Dimo account. */
  shared: boolean;
  /** Was shared, and one of you stopped; entries remain as history. */
  stopped: boolean;
}

function fromSummary(summary: LendContactSummary, active: boolean): LendPerson {
  return {
    contactId: summary.contactId,
    contactName: summary.contactName,
    balance: summary.balance,
    ...(summary.currency ? { currency: summary.currency } : {}),
    lastOccurredAt: summary.lastOccurredAt,
    entryCount: summary.entryCount,
    shared: summary.shared && active,
    stopped: summary.shared && !active,
  };
}

const SETTLED = 0.0001;

const monthDay = new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric" });
const monthDayYear = new Intl.DateTimeFormat(undefined, {
  month: "short",
  day: "numeric",
  year: "numeric",
});

/** "Today", "Yesterday", "Aug 22", or "Aug 22, 2025" for other years. */
function shortDay(timestamp: number, now = new Date()) {
  const date = new Date(timestamp);
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  if (timestamp >= startOfToday) return "Today";
  if (timestamp >= startOfToday - 86_400_000) return "Yesterday";
  return (date.getFullYear() === now.getFullYear() ? monthDay : monthDayYear).format(date);
}

function usePeople() {
  const { lends } = useAppState("lends");
  const { outgoingInvites, activeConnection } = useLendingSharing();
  return useMemo(() => {
    const recorded = allLendContactSummaries(lends).map((summary) =>
      fromSummary(summary, Boolean(activeConnection(summary.contactId))),
    );
    const invitedOnly = outgoingInvites
      .filter((invite) => invite.contactId && !recorded.some((p) => p.contactId === invite.contactId))
      .map((invite) => ({
        contactId: invite.contactId!,
        contactName: invite.contactName,
        balance: 0,
        lastOccurredAt: invite.createdAt,
        entryCount: 0,
        shared: false,
        stopped: false,
      }));
    const all = [...recorded, ...invitedOnly];
    return {
      active: all
        .filter((person) => Math.abs(person.balance) > SETTLED)
        .sort((a, b) => Math.abs(b.balance) - Math.abs(a.balance)),
      settled: all
        .filter((person) => Math.abs(person.balance) <= SETTLED)
        .sort((a, b) => b.lastOccurredAt - a.lastOccurredAt),
    };
  }, [lends, outgoingInvites, activeConnection]);
}

function PersonRow({ person, onOpen }: { person: LendPerson; onOpen: () => void }) {
  const { currency } = useAppState("currency");
  const sharing = useLendingSharing();
  const pending = sharing.pendingInvite(person.contactId);
  const settled = Math.abs(person.balance) <= SETTLED;
  const when = person.entryCount > 0 ? shortDay(person.lastOccurredAt) : null;
  const count =
    person.entryCount > 0
      ? `${person.entryCount} ${person.entryCount === 1 ? "entry" : "entries"}`
      : null;
  const status = pending
    ? "Invite pending"
    : [person.shared ? "Shared" : person.stopped ? "Sharing stopped" : count, when]
        .filter(Boolean)
        .join(" · ");
  return (
    <button
      type="button"
      onClick={onOpen}
      className="flex w-full items-center gap-3 border-b border-line-soft px-4 py-3 text-left last:border-b-0 hover:bg-canvas/60"
    >
      <Avatar
        initial={person.contactName.charAt(0).toUpperCase()}
        src={sharing.photoFor(person.contactId)}
        size={40}
        radius={12}
        textClassName="text-sm"
      />
      <div className="min-w-0 flex-1">
        <div className="truncate text-sm font-medium text-ink">{person.contactName}</div>
        <div
          className={cn(
            "mt-0.5 truncate text-xs",
            person.shared ? "text-green" : "text-muted",
          )}
        >
          {status}
        </div>
      </div>
      {settled ? null : (
        <div className="shrink-0 text-right">
          <div
            className={cn(
              "font-display text-[15px] font-semibold",
              person.balance > 0 ? "text-green" : "text-danger",
            )}
          >
            {money(Math.abs(person.balance), person.currency ?? currency)}
          </div>
          <div className="mt-0.5 text-[11px] text-faint">
            {person.balance > 0 ? "owes you" : "you owe"}
          </div>
        </div>
      )}
    </button>
  );
}

/** Invites to accept, then everyone with a balance, then everyone settled. */
export function LendingPeopleList({
  variant,
  onEdit,
}: {
  variant: Variant;
  onEdit: (target: LendEditorTarget) => void;
}) {
  const sharing = useLendingSharing();
  const { active, settled } = usePeople();
  const [openId, setOpenId] = useState<string | null>(null);
  const open = [...active, ...settled].find((person) => person.contactId === openId) ?? null;
  const empty = active.length === 0 && settled.length === 0;

  return (
    <div className="flex flex-col gap-4">
      {sharing.incomingInvites.map((invite) => (
        <IncomingInviteCard key={invite.inviteId} invite={invite} />
      ))}

      {active.length > 0 ? (
        <Card className="overflow-hidden">
          {active.map((person) => (
            <PersonRow key={person.contactId} person={person} onOpen={() => setOpenId(person.contactId)} />
          ))}
        </Card>
      ) : null}

      {settled.length > 0 ? (
        <div>
          <div className="mb-2 px-1 text-xs font-medium uppercase tracking-[0.08em] text-muted">
            Settled
          </div>
          <Card className="overflow-hidden">
            {settled.map((person) => (
              <PersonRow key={person.contactId} person={person} onOpen={() => setOpenId(person.contactId)} />
            ))}
          </Card>
        </div>
      ) : null}

      {empty ? (
        <div className="py-12 text-center">
          <div className="font-display text-base font-semibold text-ink">Nothing recorded yet</div>
          <div className="mx-auto mt-2 max-w-xs text-[13px] leading-5 text-muted">
            Add an entry when you give or get money. Pick someone on Dimo and you’ll both see it.
          </div>
        </div>
      ) : null}

      {open ? (
        <LendPersonDialog
          variant={variant}
          person={open}
          onClose={() => setOpenId(null)}
          onEdit={onEdit}
        />
      ) : null}
    </div>
  );
}


/** One person: balance, "I gave / I got", their history, and sharing controls. */
function LendPersonDialog({
  variant,
  person,
  onClose,
  onEdit,
}: {
  variant: Variant;
  person: LendPerson;
  onClose: () => void;
  onEdit: (target: LendEditorTarget) => void;
}) {
  const { lends, currency } = useAppState("lends", "currency");
  const sharing = useLendingSharing();
  const { showToast } = useAppActions();
  const [cancelTarget, setCancelTarget] = useState<OutgoingLendInvite | null>(null);
  const [confirmStop, setConfirmStop] = useState(false);
  const [linking, setLinking] = useState(false);
  const entries = useMemo(
    () =>
      lends
        .filter((lend) => lend.contactId === person.contactId)
        .sort((a, b) => b.occurredAt - a.occurredAt),
    [lends, person.contactId],
  );
  const pending = sharing.pendingInvite(person.contactId);
  const connected = sharing.activeConnection(person.contactId);
  const settled = Math.abs(person.balance) <= SETTLED;
  const shownCurrency = person.currency ?? currency;
  // Nudge towards whichever direction settles the balance.
  const settles: LendFlow | null = settled ? null : person.balance > 0 ? "got" : "gave";

  function add(flow: LendFlow) {
    onEdit({ mode: "new", contactId: person.contactId, contactName: person.contactName, flow });
  }

  return (
    <>
      <Frame
        variant={variant}
        title={person.contactName}
        onClose={onClose}
        layout="fill"
        headerRight={
          connected ? (
            <OverflowMenu
              label={`More options for ${person.contactName}`}
              items={[{ label: "Stop sharing", danger: true, onSelect: () => setConfirmStop(true) }]}
            />
          ) : undefined
        }
      >
        {/* Only the history scrolls; the balance and actions stay in view. */}
        <div className="flex min-h-0 flex-1 flex-col gap-5">
          <div className="flex shrink-0 items-center gap-3">
            <Avatar
              initial={person.contactName.charAt(0).toUpperCase()}
              src={sharing.photoFor(person.contactId)}
              size={52}
              radius={15}
              textClassName="text-lg"
            />
            <div className="min-w-0 flex-1">
              <div
                className={cn(
                  "font-display text-2xl font-semibold",
                  settled ? "text-muted" : person.balance > 0 ? "text-green" : "text-danger",
                )}
              >
                {settled ? "All settled" : money(Math.abs(person.balance), shownCurrency)}
              </div>
              <div className="mt-0.5 text-xs text-muted">
                {settled
                  ? person.shared
                    ? "Shared"
                    : pending
                      ? "Invite pending"
                      : person.stopped
                        ? "Sharing stopped"
                        : "Nothing owed either way"
                  : `${person.balance > 0 ? "Owes you" : "You owe"}${person.shared ? " · Shared" : pending ? " · Invite pending" : person.stopped ? " · Sharing stopped" : ""}`}
              </div>
            </div>
          </div>

          <div className="grid shrink-0 grid-cols-2 gap-2">
            <Button
              variant={settles === "gave" ? "primary" : "secondary"}
              size="sm"
              onClick={() => add("gave")}
            >
              I gave
            </Button>
            <Button
              variant={settles === "got" ? "primary" : "secondary"}
              size="sm"
              onClick={() => add("got")}
            >
              I got
            </Button>
          </div>

          {entries.length > 0 ? (
            <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain rounded-2xl border border-line">
              {entries.map((lend) => {
                const got = lendFlow(lend.kind) === "got";
                const flowLabel = got ? "You got" : "You gave";
                const note = lend.comment.trim();
                const detail = [note ? flowLabel : null, shortDay(lend.occurredAt), lendAttribution(lend)]
                  .filter(Boolean)
                  .join(" · ");
                return (
                  <button
                    type="button"
                    key={lend.id}
                    onClick={() => onEdit({ mode: "edit", lend })}
                    className="flex w-full items-center gap-3 border-b border-line-soft px-4 py-3 text-left last:border-b-0 hover:bg-canvas/60"
                  >
                    <div className="min-w-0 flex-1">
                      <div className="truncate text-sm text-ink">{note || flowLabel}</div>
                      <div className="mt-0.5 truncate text-xs text-muted">{detail}</div>
                    </div>
                    <div
                      className={cn(
                        "shrink-0 font-display text-[15px] font-semibold",
                        got ? "text-green" : "text-danger",
                      )}
                    >
                      {money(lend.amount, lend.currency ?? currency)}
                    </div>
                  </button>
                );
              })}
            </div>
          ) : (
            <p className="text-center text-[13px] text-muted">No entries yet.</p>
          )}

          {connected ? null : pending ? (
            <button
              type="button"
              onClick={() => setCancelTarget(pending)}
              className="shrink-0 self-center text-[13px] font-medium text-muted hover:text-danger"
            >
              Cancel invite
            </button>
          ) : person.stopped ? (
            <div className="shrink-0 rounded-2xl bg-canvas px-4 py-3.5 text-center">
              <p className="text-[13px] leading-5 text-muted">
                Changes no longer reach {person.contactName}. Share again to bring both sides back
                in step.
              </p>
              <Button
                variant="secondary"
                size="sm"
                className="mt-2.5"
                onClick={() => {
                  sharing
                    .shareAgain(person.contactId)
                    .then(() => showToast(`Invite sent to ${person.contactName}`))
                    .catch((cause) => showToast(sharingErrorText(cause)));
                }}
              >
                Share again
              </Button>
            </div>
          ) : !isSharedLendContact(person.contactId) ? (
            <div className="shrink-0 rounded-2xl bg-canvas px-4 py-3.5 text-center">
              <p className="text-[13px] leading-5 text-muted">
                Is {person.contactName} on Dimo? Link them and you’ll both see this history.
              </p>
              <Button variant="secondary" size="sm" className="mt-2.5" onClick={() => setLinking(true)}>
                Link to Dimo account
              </Button>
            </div>
          ) : null}
        </div>
      </Frame>
      {linking ? (
        <LinkAccountDialog variant={variant} person={person} onClose={() => setLinking(false)} />
      ) : null}
      <CancelInviteDialog invite={cancelTarget} onClose={() => setCancelTarget(null)} />
      <ConfirmDialog
        open={confirmStop}
        title={`Stop sharing with ${person.contactName}?`}
        message="You both keep the entries so far, but new changes won’t reach each other."
        confirmLabel="Stop sharing"
        onCancel={() => setConfirmStop(false)}
        onConfirm={() => {
          setConfirmStop(false);
          void sharing.stopSharing(person.contactId);
        }}
      />
    </>
  );
}

/**
 * Finds the Dimo account for someone already tracked and invites them for
 * this contact, so accepting shares the existing history.
 */
function LinkAccountDialog({
  variant,
  person,
  onClose,
}: {
  variant: Variant;
  person: LendPerson;
  onClose: () => void;
}) {
  const { showToast, renameLendContact } = useAppActions();
  const sharing = useLendingSharing();
  const [query, setQuery] = useState(person.contactName);
  const [results, setResults] = useState<{ query: string; users: LendUser[] } | null>(null);
  const [sending, setSending] = useState(false);
  const trimmed = query.trim();
  const users = results?.query === trimmed ? results.users : null;

  useEffect(() => {
    if (trimmed.length < 2) return;
    let cancelled = false;
    const timer = setTimeout(() => {
      sharing
        .searchUsers(trimmed)
        .then((found) => {
          if (!cancelled) setResults({ query: trimmed, users: found });
        })
        .catch(() => undefined);
    }, 250);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [trimmed, sharing]);

  function link(user: LendUser) {
    if (user.relation === "connected") {
      showToast(`You already share with ${user.name}`);
      return;
    }
    if (user.relation === "invitedYou") {
      showToast(`${user.name} already invited you. Accept their invite first.`);
      return;
    }
    setSending(true);
    sharing
      .sendInvite({ userId: user.userId, contactId: person.contactId, contactName: user.name })
      .then(() => {
        // They're now known by their account name, even before accepting.
        renameLendContact(person.contactId, user.name);
        showToast(`Invite sent to ${user.name}`);
        onClose();
      })
      .catch((cause) => showToast(sharingErrorText(cause)))
      .finally(() => setSending(false));
  }

  return (
    <Frame variant={variant} title="Link to Dimo account" onClose={onClose}>
      <div className="flex flex-col gap-3">
        <p className="text-[13px] leading-5 text-muted">
          Find {person.contactName} on Dimo. Once they accept, your entries with them are shared
          and either of you can add or edit them.
        </p>
        <TextField
          label="Their name or email"
          value={query}
          onChange={setQuery}
          placeholder="Name or email"
        />
        {users && users.length > 0 ? (
          <div className="overflow-hidden rounded-xl border border-line">
            {users.map((user) => (
              <button
                type="button"
                key={user.userId}
                disabled={sending}
                onClick={() => link(user)}
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
                  <span className="block truncate text-sm font-medium text-ink">{user.name}</span>
                  {user.email ? (
                    <span className="block truncate text-xs text-muted">{user.email}</span>
                  ) : null}
                </span>
                <span className="shrink-0 text-xs font-medium text-green">
                  {user.relation === "connected"
                    ? "Shared"
                    : user.relation === "invited"
                      ? "Invited"
                      : user.relation === "invitedYou"
                        ? "Invited you"
                        : "Link"}
                </span>
              </button>
            ))}
          </div>
        ) : users ? (
          <p className="text-[13px] text-muted">No one on Dimo matches “{trimmed}”.</p>
        ) : null}
      </div>
    </Frame>
  );
}

/** A "⋯" button with a small menu, for actions that shouldn't be up front. */
function OverflowMenu({
  label,
  items,
}: {
  label: string;
  items: Array<{ label: string; danger?: boolean; onSelect: () => void }>;
}) {
  const [open, setOpen] = useState(false);
  return (
    <div className="relative">
      <button
        type="button"
        aria-label={label}
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
        className="flex h-9 w-9 items-center justify-center rounded-xl text-lg leading-none text-muted hover:bg-canvas"
      >
        ⋯
      </button>
      {open ? (
        <>
          <button
            type="button"
            aria-hidden
            tabIndex={-1}
            onClick={() => setOpen(false)}
            className="fixed inset-0 z-10 cursor-default"
          />
          <div
            role="menu"
            className="absolute right-0 top-10 z-20 min-w-44 overflow-hidden rounded-xl border border-line bg-popup py-1 shadow-[0_12px_32px_rgba(0,0,0,0.18)]"
          >
            {items.map((item) => (
              <button
                type="button"
                role="menuitem"
                key={item.label}
                onClick={() => {
                  setOpen(false);
                  item.onSelect();
                }}
                className={cn(
                  "block w-full px-4 py-2.5 text-left text-sm hover:bg-canvas",
                  item.danger ? "text-danger" : "text-ink",
                )}
              >
                {item.label}
              </button>
            ))}
          </div>
        </>
      ) : null}
    </div>
  );
}
