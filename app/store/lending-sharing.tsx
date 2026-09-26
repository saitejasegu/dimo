"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { useAction, useConvexAuth, useMutation, useQuery } from "convex/react";
import { makeFunctionReference } from "convex/server";

/**
 * Ledgers shared with other Dimo accounts (`convex/lending.ts`). Entries arrive
 * through normal sync because the server mirrors them into this account's
 * lends; this context covers invites and connections, and uses live Convex
 * queries so an invite shows up without a refresh.
 */

export type LendHistoryChoice = "both" | "inviter" | "accepter";

export interface LendInviteCode {
  code: string;
  expiresAt: number;
}

export interface LendInvitePreview {
  inviterName: string;
  status: "pending" | "accepted" | "revoked";
  expiresAt: number;
  isOwnInvite: boolean;
}

export interface IncomingLendInvite {
  code: string;
  inviterName: string;
  expiresAt: number;
}

export interface OutgoingLendInvite {
  code: string;
  contactName: string;
  contactId?: string;
  expiresAt: number;
}

export interface LendConnectionSummary {
  connectionId: string;
  contactId: string;
  contactName: string;
  status: "active" | "revoked";
  createdAt: number;
  revokedAt?: number;
}

type NoArgs = Record<string, never>;

/** Stable empty list so memoised consumers do not churn while loading. */
const EMPTY: never[] = [];

const refs = {
  createInvite: makeFunctionReference<
    "mutation",
    { contactId?: string; contactName: string },
    LendInviteCode
  >("lending:createLendInvite"),
  inviteByEmail: makeFunctionReference<
    "mutation",
    { email: string; contactId?: string; contactName: string },
    LendInviteCode
  >("lending:inviteLendContactByEmail"),
  cancelInvite: makeFunctionReference<"mutation", { code: string }, null>(
    "lending:cancelLendInvite",
  ),
  declineInvite: makeFunctionReference<"mutation", { code: string }, null>(
    "lending:declineLendInvite",
  ),
  previewInvite: makeFunctionReference<"query", { code: string }, LendInvitePreview | null>(
    "lending:previewLendInvite",
  ),
  acceptInvite: makeFunctionReference<
    "mutation",
    { code: string; contactId?: string; contactName?: string; history: LendHistoryChoice },
    { connectionId: string; contactId: string }
  >("lending:acceptLendInvite"),
  revokeConnection: makeFunctionReference<"mutation", { connectionId: string }, null>(
    "lending:revokeLendConnection",
  ),
  connections: makeFunctionReference<"query", NoArgs, LendConnectionSummary[]>(
    "lending:listLendConnections",
  ),
  incoming: makeFunctionReference<"query", NoArgs, IncomingLendInvite[]>(
    "lending:listIncomingLendInvites",
  ),
  outgoing: makeFunctionReference<"query", NoArgs, OutgoingLendInvite[]>(
    "lending:listOutgoingLendInvites",
  ),
  refreshVerifiedEmail: makeFunctionReference<
    "action",
    NoArgs,
    { available: boolean; email: string | null }
  >("lendingEmail:refreshVerifiedEmail"),
};

export const INVITE_WEB_BASE = "https://dimoapp.xyz/invite";
/** Session key an `/invite` link parks its code under across the sign-in redirect. */
export const PENDING_INVITE_STORAGE_KEY = "dimo.pendingLendInvite";

/** Same normalisation as the server: uppercase letters and digits only. */
export function normalizeInviteCode(code: string) {
  return code.toUpperCase().replace(/[^A-Z0-9]/g, "");
}

export function groupedInviteCode(code: string) {
  return code.length === 10 ? `${code.slice(0, 5)}-${code.slice(5)}` : code;
}

export function inviteLink(code: string) {
  return `${INVITE_WEB_BASE}?code=${encodeURIComponent(code)}`;
}

/** Plain-text invite, matching the native share sheets. */
export function inviteMessage(inviterName: string, code: string) {
  return (
    `${inviterName} wants to keep a shared lending ledger with you on Dimo.\n\n` +
    `Open ${inviteLink(code)}\n` +
    `or enter code ${groupedInviteCode(code)} in Dimo → Lending → Join.`
  );
}

function takePendingInviteCode(): string | null {
  if (typeof window === "undefined") return null;
  try {
    const code = sessionStorage.getItem(PENDING_INVITE_STORAGE_KEY);
    if (code) sessionStorage.removeItem(PENDING_INVITE_STORAGE_KEY);
    const normalized = code ? normalizeInviteCode(code) : "";
    return normalized || null;
  } catch {
    return null;
  }
}

/**
 * Live preview of an invite code; `undefined` while loading, `null` when no
 * invite matches. Pass `null` to skip.
 */
export function useLendInvitePreview(code: string | null) {
  const { isAuthenticated } = useConvexAuth();
  return useQuery(
    refs.previewInvite,
    code && isAuthenticated ? { code: normalizeInviteCode(code) } : "skip",
  );
}

/** Which sharing dialog is open. */
export type LedgerSharingDialog =
  | { kind: "invite"; contactId?: string; contactName: string }
  | { kind: "join"; code: string };

interface LendingSharingValue {
  connections: LendConnectionSummary[];
  incomingInvites: IncomingLendInvite[];
  outgoingInvites: OutgoingLendInvite[];
  emailInvitesAvailable: boolean;
  dialog: LedgerSharingDialog | null;
  setDialog: (dialog: LedgerSharingDialog | null) => void;
  activeConnection: (contactId: string) => LendConnectionSummary | undefined;
  pendingInvite: (contactId: string) => OutgoingLendInvite | undefined;
  createInvite: (input: {
    contactId?: string;
    contactName: string;
    email?: string;
  }) => Promise<LendInviteCode>;
  accept: (input: {
    code: string;
    contactId?: string;
    contactName?: string;
    history: LendHistoryChoice;
  }) => Promise<void>;
  decline: (code: string) => Promise<void>;
  cancel: (code: string) => Promise<void>;
  stopSharing: (contactId: string) => Promise<void>;
}

const LendingSharingContext = createContext<LendingSharingValue | null>(null);

export function LendingSharingProvider({
  children,
  onOpenLending,
}: {
  children: ReactNode;
  /** Switches to the Lending screen when an invite link is being handled. */
  onOpenLending: () => void;
}) {
  const { isAuthenticated } = useConvexAuth();
  // Queries throw without auth, so they wait until the session is ready.
  const queryArgs = isAuthenticated ? {} : "skip";
  const connections = useQuery(refs.connections, queryArgs) ?? EMPTY;
  const incoming = useQuery(refs.incoming, queryArgs) ?? EMPTY;
  const outgoing = useQuery(refs.outgoing, queryArgs) ?? EMPTY;
  const createInviteMutation = useMutation(refs.createInvite);
  const inviteByEmailMutation = useMutation(refs.inviteByEmail);
  const cancelMutation = useMutation(refs.cancelInvite);
  const declineMutation = useMutation(refs.declineInvite);
  const acceptMutation = useMutation(refs.acceptInvite);
  const revokeMutation = useMutation(refs.revokeConnection);
  const refreshVerifiedEmail = useAction(refs.refreshVerifiedEmail);
  const [emailInvitesAvailable, setEmailInvitesAvailable] = useState(true);
  // An `/invite?code=` link parks its code in session storage (surviving the
  // sign-in redirect); the join dialog opens with it once signed in.
  const [dialog, setDialog] = useState<LedgerSharingDialog | null>(() => {
    const code = takePendingInviteCode();
    return code ? { kind: "join", code } : null;
  });
  const openedFromLink = useRef(dialog?.kind === "join");
  const [now, setNow] = useState(() => Date.now());

  // Record the verified sign-in email once per session so invites addressed
  // by email can reach this account.
  useEffect(() => {
    if (!isAuthenticated) return;
    let cancelled = false;
    refreshVerifiedEmail({})
      .then((result) => {
        if (!cancelled) setEmailInvitesAvailable(result.available);
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [isAuthenticated, refreshVerifiedEmail]);

  // Expiry is compared on the client because queries must not read the clock.
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 60_000);
    return () => clearInterval(timer);
  }, []);

  useEffect(() => {
    if (openedFromLink.current) onOpenLending();
    // Runs once: only the link that was pending at sign-in switches screens.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const incomingInvites = useMemo(
    () => incoming.filter((invite) => invite.expiresAt > now),
    [incoming, now],
  );
  const outgoingInvites = useMemo(
    () => outgoing.filter((invite) => invite.expiresAt > now),
    [outgoing, now],
  );

  const activeConnection = useCallback(
    (contactId: string) =>
      connections.find(
        (connection) => connection.contactId === contactId && connection.status === "active",
      ),
    [connections],
  );
  const pendingInvite = useCallback(
    (contactId: string) => outgoingInvites.find((invite) => invite.contactId === contactId),
    [outgoingInvites],
  );

  const value = useMemo<LendingSharingValue>(
    () => ({
      connections,
      incomingInvites,
      outgoingInvites,
      emailInvitesAvailable,
      dialog,
      setDialog,
      activeConnection,
      pendingInvite,
      createInvite: async ({ contactId, contactName, email }) => {
        const trimmedEmail = email?.trim();
        const base = {
          contactName: contactName.trim(),
          ...(contactId ? { contactId } : {}),
        };
        return trimmedEmail
          ? inviteByEmailMutation({ ...base, email: trimmedEmail })
          : createInviteMutation(base);
      },
      accept: async ({ code, contactId, contactName, history }) => {
        await acceptMutation({
          code: normalizeInviteCode(code),
          history,
          ...(contactId ? { contactId } : {}),
          ...(contactName?.trim() ? { contactName: contactName.trim() } : {}),
        });
      },
      decline: async (code) => {
        await declineMutation({ code: normalizeInviteCode(code) });
      },
      cancel: async (code) => {
        await cancelMutation({ code });
      },
      stopSharing: async (contactId) => {
        const connection = activeConnection(contactId);
        if (connection) await revokeMutation({ connectionId: connection.connectionId });
      },
    }),
    [
      connections,
      incomingInvites,
      outgoingInvites,
      emailInvitesAvailable,
      dialog,
      activeConnection,
      pendingInvite,
      inviteByEmailMutation,
      createInviteMutation,
      acceptMutation,
      declineMutation,
      cancelMutation,
      revokeMutation,
    ],
  );

  return <LendingSharingContext.Provider value={value}>{children}</LendingSharingContext.Provider>;
}

export function useLendingSharing() {
  const value = useContext(LendingSharingContext);
  if (!value) throw new Error("useLendingSharing must be used within a LendingSharingProvider");
  return value;
}
