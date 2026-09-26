"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { useAction, useConvex, useConvexAuth, useMutation, useQuery } from "convex/react";
import { makeFunctionReference } from "convex/server";

/**
 * Ledgers shared with other Dimo accounts (`convex/lending.ts`). Entries arrive
 * through normal sync because the server mirrors them into this account's
 * lends; this context covers finding people, invites and connections, and uses
 * live Convex queries so an invite shows up without a refresh.
 */

export type LendHistoryChoice = "both" | "inviter" | "accepter";

export interface LendUser {
  userId: string;
  name: string;
  email: string;
  relation: "none" | "self" | "connected" | "invited" | "invitedYou";
  /** Your contactId for them: the shared ledger when connected, or the
   * contact a pending invite is for. */
  contactId?: string;
}

export interface IncomingLendInvite {
  inviteId: string;
  inviterName: string;
  inviterEmail?: string;
  createdAt: number;
}

export interface OutgoingLendInvite {
  inviteId: string;
  contactName: string;
  contactId?: string;
  inviteeEmail?: string;
  createdAt: number;
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
  findUser: makeFunctionReference<"query", { email: string }, LendUser | null>(
    "lending:findLendUser",
  ),
  sendInvite: makeFunctionReference<
    "mutation",
    { userId: string; contactId?: string; contactName: string },
    { inviteId: string }
  >("lending:sendLendInvite"),
  cancelInvite: makeFunctionReference<"mutation", { inviteId: string }, null>(
    "lending:cancelLendInvite",
  ),
  declineInvite: makeFunctionReference<"mutation", { inviteId: string }, null>(
    "lending:declineLendInvite",
  ),
  acceptInvite: makeFunctionReference<
    "mutation",
    { inviteId: string; contactId?: string; contactName?: string; history: LendHistoryChoice },
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

/** Which sharing dialog is open. */
export type LedgerSharingDialog = { kind: "accept"; invite: IncomingLendInvite };

interface LendingSharingValue {
  connections: LendConnectionSummary[];
  incomingInvites: IncomingLendInvite[];
  outgoingInvites: OutgoingLendInvite[];
  /** False when the deployment cannot verify emails, so nobody can be found. */
  sharingAvailable: boolean;
  dialog: LedgerSharingDialog | null;
  setDialog: (dialog: LedgerSharingDialog | null) => void;
  activeConnection: (contactId: string) => LendConnectionSummary | undefined;
  pendingInvite: (contactId: string) => OutgoingLendInvite | undefined;
  findUser: (email: string) => Promise<LendUser | null>;
  sendInvite: (input: { userId: string; contactId: string; contactName: string }) => Promise<void>;
  accept: (input: {
    inviteId: string;
    contactId?: string;
    contactName?: string;
    history: LendHistoryChoice;
  }) => Promise<void>;
  decline: (inviteId: string) => Promise<void>;
  cancel: (inviteId: string) => Promise<void>;
  stopSharing: (contactId: string) => Promise<void>;
}

const LendingSharingContext = createContext<LendingSharingValue | null>(null);

export function LendingSharingProvider({ children }: { children: ReactNode }) {
  const convex = useConvex();
  const { isAuthenticated } = useConvexAuth();
  // Queries throw without auth, so they wait until the session is ready.
  const queryArgs = isAuthenticated ? {} : "skip";
  const connections = useQuery(refs.connections, queryArgs) ?? EMPTY;
  const incomingInvites = useQuery(refs.incoming, queryArgs) ?? EMPTY;
  const outgoingInvites = useQuery(refs.outgoing, queryArgs) ?? EMPTY;
  const sendMutation = useMutation(refs.sendInvite);
  const cancelMutation = useMutation(refs.cancelInvite);
  const declineMutation = useMutation(refs.declineInvite);
  const acceptMutation = useMutation(refs.acceptInvite);
  const revokeMutation = useMutation(refs.revokeConnection);
  const refreshVerifiedEmail = useAction(refs.refreshVerifiedEmail);
  const [sharingAvailable, setSharingAvailable] = useState(true);
  const [dialog, setDialog] = useState<LedgerSharingDialog | null>(null);

  // Record the verified sign-in email once per session so other people can
  // find this account.
  useEffect(() => {
    if (!isAuthenticated) return;
    let cancelled = false;
    refreshVerifiedEmail({})
      .then((result) => {
        if (!cancelled) setSharingAvailable(result.available);
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [isAuthenticated, refreshVerifiedEmail]);

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
      sharingAvailable,
      dialog,
      setDialog,
      activeConnection,
      pendingInvite,
      findUser: (email) => convex.query(refs.findUser, { email: email.trim() }),
      sendInvite: async ({ userId, contactId, contactName }) => {
        await sendMutation({ userId, contactId, contactName: contactName.trim() });
      },
      accept: async ({ inviteId, contactId, contactName, history }) => {
        await acceptMutation({
          inviteId,
          history,
          ...(contactId ? { contactId } : {}),
          ...(contactName?.trim() ? { contactName: contactName.trim() } : {}),
        });
      },
      decline: async (inviteId) => {
        await declineMutation({ inviteId });
      },
      cancel: async (inviteId) => {
        await cancelMutation({ inviteId });
      },
      stopSharing: async (contactId) => {
        const connection = activeConnection(contactId);
        if (connection) await revokeMutation({ connectionId: connection.connectionId });
      },
    }),
    [
      convex,
      connections,
      incomingInvites,
      outgoingInvites,
      sharingAvailable,
      dialog,
      activeConnection,
      pendingInvite,
      sendMutation,
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
