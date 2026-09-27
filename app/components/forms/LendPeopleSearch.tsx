"use client";

import { useEffect, useMemo, useState } from "react";
import { useAppActions, useAppState } from "@/store/app-store";
import { useLendingSharing, type LendUser } from "@/store/lending-sharing";
import { recentLendContacts, type LendContactSuggestion } from "@/features/lending/selectors";
import { Avatar } from "@/components/ui/Avatar";

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

/**
 * People the user can record money with: recent contacts, active shared
 * ledgers and pending invites as one-tap `suggestions`, plus everyone ever
 * recorded as `knownContacts` for matching what's typed.
 */
export function useLendPeople() {
  const { lends } = useAppState("lends");
  const { connections, outgoingInvites } = useLendingSharing();

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

  const knownContacts = useMemo(() => {
    const all = recentLendContacts(lends, Number.MAX_SAFE_INTEGER);
    for (const suggestion of suggestions) {
      if (!all.some((contact) => contact.contactId === suggestion.contactId)) all.push(suggestion);
    }
    return all;
  }, [lends, suggestions]);

  return { suggestions, knownContacts };
}

/**
 * Matches for a typed name or email: the user's own people first, then Dimo
 * accounts. Renders nothing until there is something to show.
 */
export function LendPeopleResults({
  query,
  knownContacts,
  excludeContactIds,
  onPickContact,
  onPickUser,
}: {
  query: string;
  knownContacts: LendContactSuggestion[];
  /** People already picked elsewhere in the form. */
  excludeContactIds?: ReadonlySet<string>;
  onPickContact: (contact: LendContactSuggestion) => void;
  /** Never called for someone who already invited the user. */
  onPickUser: (user: LendUser) => void;
}) {
  const { showToast } = useAppActions();
  const sharing = useLendingSharing();
  const [search, setSearch] = useState<DimoSearch | null>(null);
  const searchable = query.length >= MIN_SEARCH_LENGTH;
  const dimoResults = searchable && search?.query === query
    ? search.users.filter((user) => !user.contactId || !excludeContactIds?.has(user.contactId))
    : null;

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

  const matchingContacts = useMemo(() => {
    const needle = query.toLowerCase();
    // A Dimo result already stands for the contact it's shared or invited as.
    const linked = new Set((dimoResults ?? []).map((user) => user.contactId));
    return knownContacts
      .filter((contact) => contact.contactName.toLowerCase().includes(needle))
      .filter((contact) => !linked.has(contact.contactId))
      .filter((contact) => !excludeContactIds?.has(contact.contactId))
      .slice(0, 5);
  }, [query, knownContacts, dimoResults, excludeContactIds]);

  function pickUser(user: LendUser) {
    if (user.relation === "invitedYou") {
      showToast(`${user.name} already invited you. Accept their invite in Lending first.`);
      return;
    }
    onPickUser(user);
  }

  if (matchingContacts.length === 0 && dimoResults === null) return null;

  return (
    <div className="mt-2 overflow-hidden rounded-xl border border-line bg-surface">
      {matchingContacts.map((contact) => (
        <button
          type="button"
          key={contact.contactId}
          onClick={() => onPickContact(contact)}
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
          onClick={() => pickUser(user)}
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
          <span className="shrink-0 text-xs font-medium text-green">{relationLabel(user)}</span>
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
  );
}
