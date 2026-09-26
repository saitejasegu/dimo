"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  type ReactNode,
} from "react";
import { useConvex, useConvexAuth, useMutation, useQuery } from "convex/react";
import { makeFunctionReference } from "convex/server";
import { useAppState } from "@/store/app-store";

/**
 * Ledgers shared with other Dimo accounts (`convex/lending.ts`). Entries arrive
 * through normal sync because the server mirrors them into this account's
 * lends; this context covers finding people, invites and connections, and uses
 * live Convex queries so an invite shows up without a refresh.
 */

export type LendHistoryChoice = "both" | "inviter" | "accepter";

/** The readable sentence from a Convex error (it prefixes request metadata). */
export function sharingErrorText(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  const tail = message.split("Uncaught Error:").pop() ?? message;
  return tail.trim().split("\n")[0];
}

export interface LendUser {
  userId: string;
  name: string;
  email?: string;
  photoUrl?: string;
  relation: "none" | "connected" | "invited" | "invitedYou";
  /** Your contactId for them: the shared ledger when connected, or the
   * contact a pending invite is for. */
  contactId?: string;
}

export interface IncomingLendInvite {
  inviteId: string;
  inviterName: string;
  inviterEmail?: string;
  inviterPhotoUrl?: string;
  /** Turns a stopped share back on. */
  reconnect: boolean;
  createdAt: number;
}

export interface OutgoingLendInvite {
  inviteId: string;
  contactName: string;
  contactId?: string;
  inviteeEmail?: string;
  inviteePhotoUrl?: string;
  createdAt: number;
}

export interface LendConnectionSummary {
  connectionId: string;
  contactId: string;
  contactName: string;
  status: "active" | "revoked";
  createdAt: number;
  revokedAt?: number;
  /** The other member's profile photo. */
  photoUrl?: string;
}

type NoArgs = Record<string, never>;

/** Stable empty list so memoised consumers do not churn while loading. */
const EMPTY: never[] = [];

const refs = {
  searchUsers: makeFunctionReference<"query", { query: string }, LendUser[]>(
    "lending:searchLendUsers",
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
  setProfilePhoto: makeFunctionReference<"mutation", { photoUrl: string | null }, null>(
    "lending:setProfilePhoto",
  ),
  reshare: makeFunctionReference<"mutation", { connectionId: string }, { inviteId: string }>(
    "lending:reshareLendConnection",
  ),
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
};


interface LendingSharingValue {
  connections: LendConnectionSummary[];
  incomingInvites: IncomingLendInvite[];
  outgoingInvites: OutgoingLendInvite[];
  activeConnection: (contactId: string) => LendConnectionSummary | undefined;
  pendingInvite: (contactId: string) => OutgoingLendInvite | undefined;
  /** Profile photo for a shared or invited contact, if they have one. */
  photoFor: (contactId: string) => string | undefined;
  /** Dimo accounts (never this one) matching a name or email. */
  searchUsers: (query: string) => Promise<LendUser[]>;
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
  /** Invites the other person to share a stopped connection again. */
  shareAgain: (contactId: string) => Promise<void>;
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
  const reshareMutation = useMutation(refs.reshare);
  const setProfilePhoto = useMutation(refs.setProfilePhoto);
  const { profile } = useAppState("profile");

  // Publish this account's sign-in photo so people it shares lending with see it.
  const photoUrl = profile.photoUrl ?? null;
  useEffect(() => {
    if (!isAuthenticated) return;
    void setProfilePhoto({ photoUrl }).catch(() => undefined);
  }, [isAuthenticated, photoUrl, setProfilePhoto]);

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

  const photoFor = useCallback(
    (contactId: string) =>
      connections.find((connection) => connection.contactId === contactId)?.photoUrl ??
      outgoingInvites.find((invite) => invite.contactId === contactId)?.inviteePhotoUrl,
    [connections, outgoingInvites],
  );

  const value = useMemo<LendingSharingValue>(
    () => ({
      connections,
      incomingInvites,
      outgoingInvites,
      activeConnection,
      pendingInvite,
      photoFor,
      searchUsers: (query) => convex.query(refs.searchUsers, { query: query.trim() }),
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
      shareAgain: async (contactId) => {
        const connection = connections.find((item) => item.contactId === contactId);
        if (connection) await reshareMutation({ connectionId: connection.connectionId });
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
      activeConnection,
      pendingInvite,
      photoFor,
      sendMutation,
      acceptMutation,
      declineMutation,
      cancelMutation,
      revokeMutation,
      reshareMutation,
    ],
  );

  return <LendingSharingContext.Provider value={value}>{children}</LendingSharingContext.Provider>;
}

export function useLendingSharing() {
  const value = useContext(LendingSharingContext);
  if (!value) throw new Error("useLendingSharing must be used within a LendingSharingProvider");
  return value;
}
