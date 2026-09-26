/**
 * Collaborative lending between two Dimo accounts.
 *
 * Every account keeps its own `lends` rows so the existing per-owner revision
 * sync keeps working. An entry whose contactId is `dimo:<connectionId>` is
 * shared: its authoritative copy lives in `sharedLends`, and every accepted
 * write is mirrored into both members' `lends` with the direction flipped for
 * the other member (lent ↔ borrowed, repaid ↔ returned). Either member may
 * edit; conflicts resolve last-write-wins on the shared copy's version.
 */
import { makeFunctionReference } from "convex/server";
import { v, type Infer } from "convex/values";
import {
  internalMutation,
  mutation,
  query,
  type MutationCtx,
  type QueryCtx,
} from "./_generated/server";
import type { Doc, Id } from "./_generated/dataModel";
import { compareVersions, getTypedRow, type Version } from "./compat";
import {
  lendKindValidator,
  type lendOperationValidator,
} from "./values";
import {
  loadWorkspace,
  persistWorkspace,
  requireIdentity,
  type AuthIdentity,
} from "./workspace";

type LendKind = Infer<typeof lendKindValidator>;
type LendOperation = Infer<typeof lendOperationValidator>;
type Connection = Doc<"lendConnections">;

const WORKSPACE_ID = "global";
export const SHARED_CONTACT_PREFIX = "dimo:";
const MAX_PENDING_INVITES = 20;
const LINK_BATCH_SIZE = 50;
const LIST_LIMIT = 100;
const SERVER_DEVICE_ID = "convex-lend-share";
const MAX_NAME_LENGTH = 120;

const FLIPPED_KIND: Record<LendKind, LendKind> = {
  lent: "borrowed",
  borrowed: "lent",
  repaid: "returned",
  returned: "repaid",
};

const linkLendHistoryRef = makeFunctionReference<"mutation">(
  "lending:linkLendHistory",
);
const purgeSharedLendsRef = makeFunctionReference<"mutation">(
  "lending:purgeSharedLends",
);
const relinkLendHistoryRef = makeFunctionReference<"mutation">(
  "lending:relinkLendHistory",
);

export function sharedContactId(connectionId: Id<"lendConnections">) {
  return `${SHARED_CONTACT_PREFIX}${connectionId}`;
}

function isMember(connection: Connection, ownerId: string) {
  return connection.memberA === ownerId || connection.memberB === ownerId;
}

function otherMember(connection: Connection, ownerId: string) {
  return connection.memberA === ownerId ? connection.memberB : connection.memberA;
}

/** Name `ownerId` uses for the other member. */
function contactNameFor(connection: Connection, ownerId: string) {
  return connection.memberA === ownerId
    ? connection.contactNameForA
    : connection.contactNameForB;
}

/** Converts between memberA's direction and `ownerId`'s direction (an involution). */
function kindBetween(connection: Connection, ownerId: string, kind: LendKind) {
  return connection.memberA === ownerId ? kind : FLIPPED_KIND[kind];
}

function cleanName(value: string | undefined) {
  const trimmed = (value ?? "").trim();
  if (trimmed.length > MAX_NAME_LENGTH) throw new Error("Name is too long");
  return trimmed;
}

/** Version a server-side rewrite uses so it wins over the row it replaces. */
function serverVersion(previous: Version, now: number): Version {
  return previous.timestamp >= now
    ? {
        timestamp: previous.timestamp,
        counter: previous.counter + 1,
        deviceId: SERVER_DEVICE_ID,
      }
    : { timestamp: now, counter: 0, deviceId: SERVER_DEVICE_ID };
}

async function findLendRow(ctx: QueryCtx, ownerId: string, entityId: string) {
  return await ctx.db
    .query("lends")
    .withIndex("by_owner_workspace_entity", (q) =>
      q.eq("ownerId", ownerId).eq("workspaceId", WORKSPACE_ID).eq("entityId", entityId),
    )
    .unique();
}

async function findSharedLend(
  ctx: QueryCtx,
  connectionId: Id<"lendConnections">,
  entityId: string,
) {
  return await ctx.db
    .query("sharedLends")
    .withIndex("by_connectionId_and_entityId", (q) =>
      q.eq("connectionId", connectionId).eq("entityId", entityId),
    )
    .unique();
}

async function findConnectionBetween(ctx: QueryCtx, first: string, second: string) {
  const forward = await ctx.db
    .query("lendConnections")
    .withIndex("by_memberA_and_memberB", (q) =>
      q.eq("memberA", first).eq("memberB", second),
    )
    .filter((q) => q.eq(q.field("status"), "active"))
    .first();
  if (forward) return forward;
  return await ctx.db
    .query("lendConnections")
    .withIndex("by_memberA_and_memberB", (q) =>
      q.eq("memberA", second).eq("memberB", first),
    )
    .filter((q) => q.eq(q.field("status"), "active"))
    .first();
}

async function preferredCurrency(ctx: QueryCtx, ownerId: string) {
  const preferences = await getTypedRow(ctx, "preferences", ownerId, WORKSPACE_ID, "preferences");
  return preferences && !preferences.deleted && typeof preferences.currency === "string"
    ? preferences.currency
    : undefined;
}

/**
 * Hands out workspace revisions for every owner a mutation touches and
 * persists the non-caller counters at the end. The caller's counter is
 * persisted by the sync path so its profile bookkeeping still runs.
 */
class RevisionBook {
  private readonly entries = new Map<
    string,
    { workspace: Doc<"workspaces"> | null; revision: number; dirty: boolean }
  >();

  constructor(private readonly ctx: MutationCtx) {}

  seed(ownerId: string, workspace: Doc<"workspaces"> | null) {
    this.entries.set(ownerId, {
      workspace,
      revision: workspace?.revision ?? 0,
      dirty: false,
    });
  }

  async next(ownerId: string) {
    let entry = this.entries.get(ownerId);
    if (!entry) {
      const workspace = await loadWorkspace(this.ctx, ownerId, WORKSPACE_ID);
      entry = { workspace, revision: workspace?.revision ?? 0, dirty: false };
      this.entries.set(ownerId, entry);
    }
    entry.revision += 1;
    entry.dirty = true;
    return entry.revision;
  }

  current(ownerId: string) {
    return this.entries.get(ownerId)?.revision ?? 0;
  }

  async flush(except?: string) {
    for (const [ownerId, entry] of this.entries) {
      if (ownerId === except || !entry.dirty) continue;
      if (entry.workspace) {
        await this.ctx.db.patch(entry.workspace._id, { revision: entry.revision });
      } else {
        await this.ctx.db.insert("workspaces", {
          ownerId,
          workspaceId: WORKSPACE_ID,
          revision: entry.revision,
        });
      }
    }
  }
}

/**
 * Writes `ownerId`'s copy of a shared entry. A different member's unrelated
 * private row with the same id is never overwritten: ids are client-chosen,
 * so a collision could otherwise be used to clobber someone else's data.
 */
async function writeProjection(
  ctx: MutationCtx,
  revisions: RevisionBook,
  connection: Connection,
  shared: Doc<"sharedLends"> | Omit<Doc<"sharedLends">, "_id" | "_creationTime">,
  ownerId: string,
  options: { allowConvertingPrivateRow: boolean },
) {
  const existing = await findLendRow(ctx, ownerId, shared.entityId);
  if (
    existing &&
    existing.connectionId !== connection._id &&
    !options.allowConvertingPrivateRow
  ) {
    throw new Error("Lend id collides with an unshared entry");
  }
  const revision = await revisions.next(ownerId);
  const row = {
    ownerId,
    workspaceId: WORKSPACE_ID,
    entityId: shared.entityId,
    version: shared.version,
    deleted: shared.deleted,
    revision,
    contactName: contactNameFor(connection, ownerId),
    contactId: sharedContactId(connection._id),
    amountMinor: shared.amountMinor,
    occurredAt: shared.occurredAt,
    comment: shared.comment,
    kind: kindBetween(connection, ownerId, shared.kindForA),
    ...(shared.currency !== undefined ? { currency: shared.currency } : {}),
    connectionId: connection._id,
    createdBy: shared.authorId === ownerId ? ("me" as const) : ("contact" as const),
    lastEditedBy: shared.lastEditorId === ownerId ? ("me" as const) : ("contact" as const),
  };
  if (existing) await ctx.db.replace(existing._id, row);
  else await ctx.db.insert("lends", row);
  return revision;
}

async function upsertShared(
  ctx: MutationCtx,
  current: Doc<"sharedLends"> | null,
  next: Omit<Doc<"sharedLends">, "_id" | "_creationTime">,
) {
  if (current) await ctx.db.replace(current._id, next);
  else await ctx.db.insert("sharedLends", next);
}

/**
 * The active connection an operation writes through, or null for a private
 * entry. A row that is already shared stays shared even if a stale client
 * sends its old address-book contactId.
 */
async function connectionForOperation(
  ctx: QueryCtx,
  ownerId: string,
  operation: LendOperation,
  current: Doc<"lends"> | null,
) {
  let connectionId: Id<"lendConnections"> | null = current?.connectionId ?? null;
  if (!connectionId && operation.contactId?.startsWith(SHARED_CONTACT_PREFIX)) {
    connectionId = ctx.db.normalizeId(
      "lendConnections",
      operation.contactId.slice(SHARED_CONTACT_PREFIX.length),
    );
    if (!connectionId) throw new Error("Unknown lending connection");
  }
  if (!connectionId) return null;
  const connection = await ctx.db.get(connectionId);
  if (!connection || !isMember(connection, ownerId)) {
    throw new Error("Not a member of this lending connection");
  }
  return connection.status === "active" ? connection : null;
}

function assertLendOperation(operation: LendOperation) {
  if (!Number.isInteger(operation.version.timestamp) || !Number.isInteger(operation.version.counter)) {
    throw new Error("Invalid logical version");
  }
  if (!Number.isInteger(operation.amountMinor) || operation.amountMinor <= 0) {
    throw new Error("Invalid minor-unit amount");
  }
}

/** Push handler behind `syncTyped:pushLends`. */
export async function pushLendOperations(
  ctx: MutationCtx,
  workspaceId: string,
  operations: LendOperation[],
) {
  const identity = await requireIdentity(ctx);
  const ownerId = identity.tokenIdentifier;
  if (workspaceId !== WORKSPACE_ID) throw new Error("Unsupported workspace");
  if (operations.length > 50) throw new Error("A push may contain at most 50 operations");

  const workspace = await loadWorkspace(ctx, ownerId, workspaceId);
  const revisions = new RevisionBook(ctx);
  revisions.seed(ownerId, workspace);
  const acknowledgements: Array<{ operationId: string; applied: boolean; revision: number }> = [];

  for (const operation of operations) {
    if (operation.workspaceId !== workspaceId) throw new Error("Workspace mismatch");
    assertLendOperation(operation);
    const current = await findLendRow(ctx, ownerId, operation.entityId);
    const connection = await connectionForOperation(ctx, ownerId, operation, current);
    const kind = operation.kind ?? "lent";

    if (!connection) {
      const applied =
        !current || compareVersions(operation.version, current.version) > 0;
      if (applied) {
        const revision = await revisions.next(ownerId);
        const row = {
          ownerId,
          workspaceId,
          entityId: operation.entityId,
          version: operation.version,
          deleted: operation.deleted,
          revision,
          contactName: operation.contactName,
          ...(operation.contactId !== undefined ? { contactId: operation.contactId } : {}),
          amountMinor: operation.amountMinor,
          occurredAt: operation.occurredAt,
          comment: operation.comment,
          ...(operation.kind !== undefined ? { kind: operation.kind } : {}),
          ...((operation.currency ?? current?.currency) !== undefined
            ? { currency: operation.currency ?? current?.currency }
            : {}),
          // A revoked connection's history keeps its labels.
          ...(current?.connectionId !== undefined
            ? {
                connectionId: current.connectionId,
                createdBy: current.createdBy,
                lastEditedBy: current.lastEditedBy,
              }
            : {}),
        };
        if (current) await ctx.db.replace(current._id, row);
        else await ctx.db.insert("lends", row);
      }
      acknowledgements.push({
        operationId: operation.operationId,
        applied,
        revision: applied ? revisions.current(ownerId) : (current?.revision ?? revisions.current(ownerId)),
      });
      continue;
    }

    const shared = await findSharedLend(ctx, connection._id, operation.entityId);
    // A private row being moved into the ledger is compared against itself.
    const baseline = shared?.version ?? current?.version;
    const applied = !baseline || compareVersions(operation.version, baseline) > 0;
    if (!applied) {
      acknowledgements.push({
        operationId: operation.operationId,
        applied: false,
        revision: current?.revision ?? revisions.current(ownerId),
      });
      continue;
    }

    const next = {
      connectionId: connection._id,
      entityId: operation.entityId,
      version: operation.version,
      deleted: operation.deleted,
      amountMinor: operation.amountMinor,
      currency:
        operation.currency ??
        shared?.currency ??
        current?.currency ??
        (await preferredCurrency(ctx, ownerId)),
      occurredAt: operation.occurredAt,
      comment: operation.comment,
      kindForA: kindBetween(connection, ownerId, kind),
      authorId: shared?.authorId ?? ownerId,
      lastEditorId: ownerId,
    };
    await upsertShared(ctx, shared, next);
    const revision = await writeProjection(ctx, revisions, connection, next, ownerId, {
      allowConvertingPrivateRow: true,
    });
    await writeProjection(ctx, revisions, connection, next, otherMember(connection, ownerId), {
      allowConvertingPrivateRow: false,
    });
    acknowledgements.push({ operationId: operation.operationId, applied: true, revision });
  }

  await revisions.flush(ownerId);
  const latestRevision = revisions.current(ownerId);
  await persistWorkspace(ctx, workspace, ownerId, workspaceId, latestRevision, identity, {});
  return { acknowledgements, latestRevision };
}

/**
 * Clears the caller's lends for a full cloud replacement. Shared copies are
 * kept by default: the other member still relies on the ledger, and a
 * re-upload would lose to the newer shared version and never recreate them.
 * Account deletion passes `includeShared`, which also revokes connections.
 */
export async function clearLendRows(
  ctx: MutationCtx,
  ownerId: string,
  take: number,
  includeShared: boolean,
): Promise<{ deleted: number; exhausted: boolean }> {
  if (take <= 0) return { deleted: 0, exhausted: false };
  if (includeShared) await revokeAllConnections(ctx, ownerId);
  const rowsQuery = () =>
    includeShared
      ? ctx.db
          .query("lends")
          .withIndex("by_owner_workspace_entity", (q) =>
            q.eq("ownerId", ownerId).eq("workspaceId", WORKSPACE_ID),
          )
      : ctx.db
          .query("lends")
          .withIndex("by_owner_workspace_connectionId", (q) =>
            q
              .eq("ownerId", ownerId)
              .eq("workspaceId", WORKSPACE_ID)
              .eq("connectionId", undefined),
          );
  const rows = await rowsQuery().take(take);
  for (const row of rows) await ctx.db.delete(row._id);
  const more = await rowsQuery().first();
  return { deleted: rows.length, exhausted: !more };
}

async function revokeConnection(ctx: MutationCtx, connection: Connection) {
  if (connection.status !== "active") return;
  await ctx.db.patch(connection._id, { status: "revoked", revokedAt: Date.now() });
  // Each member keeps their own copies as detached history; the authoritative
  // copies are no longer needed.
  await ctx.scheduler.runAfter(0, purgeSharedLendsRef, { connectionId: connection._id });
}

async function revokeAllConnections(ctx: MutationCtx, ownerId: string) {
  const asA = await ctx.db
    .query("lendConnections")
    .withIndex("by_memberA_and_memberB", (q) => q.eq("memberA", ownerId))
    .filter((q) => q.eq(q.field("status"), "active"))
    .take(LIST_LIMIT);
  const asB = await ctx.db
    .query("lendConnections")
    .withIndex("by_memberB_and_memberA", (q) => q.eq("memberB", ownerId))
    .filter((q) => q.eq(q.field("status"), "active"))
    .take(LIST_LIMIT);
  for (const connection of [...asA, ...asB]) await revokeConnection(ctx, connection);
  const invites = await ctx.db
    .query("lendInvites")
    .withIndex("by_inviterId_and_status", (q) =>
      q.eq("inviterId", ownerId).eq("status", "pending"),
    )
    .take(MAX_PENDING_INVITES * 2);
  for (const invite of invites) await ctx.db.patch(invite._id, { status: "revoked" });
}

function displayName(identity: AuthIdentity, workspace: Doc<"workspaces"> | null) {
  return workspace?.name?.trim() || identity.name?.trim() || "Dimo user";
}

export function normalizeEmail(email: string) {
  return email.trim().toLowerCase();
}

/** Email and photo another account shows the caller, when set. */
async function publicProfileOf(ctx: QueryCtx, ownerId: string) {
  const workspace = await loadWorkspace(ctx, ownerId, WORKSPACE_ID);
  const email = workspace?.email?.trim() || undefined;
  const photoUrl = workspace?.photoUrl || undefined;
  return { ...(email ? { email } : {}), ...(photoUrl ? { photoUrl } : {}) };
}

/** Hosts profile photos may come from; anything else could track viewers. */
const PHOTO_HOSTS = ["workoscdn.com", "googleusercontent.com"];

export function isAllowedPhotoUrl(value: string) {
  try {
    const url = new URL(value);
    return (
      url.protocol === "https:" &&
      value.length <= 2048 &&
      PHOTO_HOSTS.some((host) => url.hostname === host || url.hostname.endsWith(`.${host}`))
    );
  } catch {
    return false;
  }
}

/**
 * Records the caller's sign-in profile photo so people they share lending with
 * see it. Only provider-hosted images are kept; null clears it.
 */
export const setProfilePhoto = mutation({
  args: { photoUrl: v.union(v.string(), v.null()) },
  returns: v.null(),
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const photoUrl = args.photoUrl && isAllowedPhotoUrl(args.photoUrl) ? args.photoUrl : undefined;
    const workspace = await loadWorkspace(ctx, identity.tokenIdentifier, WORKSPACE_ID);
    if (!workspace || workspace.photoUrl === photoUrl) return null;
    await ctx.db.patch(workspace._id, { photoUrl });
    return null;
  },
});

async function pendingInvitesFrom(ctx: QueryCtx, inviterId: string) {
  return await ctx.db
    .query("lendInvites")
    .withIndex("by_inviterId_and_status", (q) =>
      q.eq("inviterId", inviterId).eq("status", "pending"),
    )
    .take(MAX_PENDING_INVITES * 2);
}

async function pendingInviteBetween(ctx: QueryCtx, inviterId: string, inviteeId: string) {
  return (await pendingInvitesFrom(ctx, inviterId)).find(
    (invite) => invite.inviteeId === inviteeId,
  );
}

const userRelationValidator = v.union(
  v.literal("none"),
  v.literal("connected"),
  v.literal("invited"),
  v.literal("invitedYou"),
);

const SEARCH_LIMIT = 8;
const MIN_SEARCH_LENGTH = 2;

async function describeUser(ctx: QueryCtx, ownerId: string, account: Doc<"workspaces">) {
  const email = account.email?.trim() || undefined;
  const base = {
    userId: account._id,
    name: account.name?.trim() || email?.split("@")[0] || "Dimo user",
    ...(email ? { email } : {}),
    ...(account.photoUrl ? { photoUrl: account.photoUrl } : {}),
  };
  const otherId = account.ownerId!;
  const connection = await findConnectionBetween(ctx, ownerId, otherId);
  if (connection) {
    return { ...base, relation: "connected" as const, contactId: sharedContactId(connection._id) };
  }
  if (await pendingInviteBetween(ctx, otherId, ownerId)) {
    return { ...base, relation: "invitedYou" as const };
  }
  const sent = await pendingInviteBetween(ctx, ownerId, otherId);
  if (sent) {
    return {
      ...base,
      relation: "invited" as const,
      ...(sent.contactId !== undefined ? { contactId: sent.contactId } : {}),
    };
  }
  return { ...base, relation: "none" as const };
}

/**
 * Dimo accounts matching `query`, so they can be invited to share a ledger.
 * A full email matches that account exactly; anything else is a
 * prefix-aware search over profile names. The caller is never included.
 */
export const searchLendUsers = query({
  args: { query: v.string() },
  returns: v.array(
    v.object({
      userId: v.id("workspaces"),
      name: v.string(),
      email: v.optional(v.string()),
      photoUrl: v.optional(v.string()),
      relation: userRelationValidator,
      /** The caller's contactId for them: the shared ledger when connected,
       * or the contact a pending invite is for. */
      contactId: v.optional(v.string()),
    }),
  ),
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const ownerId = identity.tokenIdentifier;
    const text = args.query.trim().slice(0, 254);
    if (text.length < MIN_SEARCH_LENGTH) return [];
    const email = normalizeEmail(text);
    const accounts = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
      ? await ctx.db
          .query("workspaces")
          .withIndex("by_email", (q) => q.eq("email", email))
          .take(SEARCH_LIMIT)
      : await ctx.db
          .query("workspaces")
          .withSearchIndex("search_name", (q) =>
            q.search("name", text).eq("workspaceId", WORKSPACE_ID),
          )
          .take(SEARCH_LIMIT + 1);
    const others = accounts
      .filter((account) => account.workspaceId === WORKSPACE_ID)
      .filter((account) => account.ownerId && account.ownerId !== ownerId)
      .slice(0, SEARCH_LIMIT);
    return await Promise.all(others.map((account) => describeUser(ctx, ownerId, account)));
  },
});

/**
 * Invites an account found by `searchLendUsers`. Until they accept, the
 * inviter's entries with `contactId` stay private.
 */
export const sendLendInvite = mutation({
  args: {
    userId: v.id("workspaces"),
    /** The inviter's local contact whose history is shared once accepted. */
    contactId: v.optional(v.string()),
    /** What the inviter calls the person being invited. */
    contactName: v.string(),
  },
  returns: v.object({ inviteId: v.id("lendInvites") }),
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const ownerId = identity.tokenIdentifier;
    const contactName = cleanName(args.contactName);
    if (!contactName) throw new Error("Contact name is required");
    const contactId = args.contactId?.trim() || undefined;
    if (contactId?.startsWith(SHARED_CONTACT_PREFIX)) {
      throw new Error("This contact is already shared");
    }
    const account = await ctx.db.get(args.userId);
    if (!account?.ownerId || account.workspaceId !== WORKSPACE_ID) throw new Error("User not found");
    const inviteeId = account.ownerId;
    if (inviteeId === ownerId) throw new Error("You cannot invite yourself");
    if (await findConnectionBetween(ctx, ownerId, inviteeId)) {
      throw new Error("You already share with this person");
    }
    if (await pendingInviteBetween(ctx, inviteeId, ownerId)) {
      throw new Error("They already invited you. Accept their invite in Lending");
    }

    const pending = await pendingInvitesFrom(ctx, ownerId);
    // A new invite to the same person or for the same contact replaces the older one.
    const replaced = pending.filter(
      (invite) => invite.inviteeId === inviteeId || (contactId && invite.contactId === contactId),
    );
    if (pending.length - replaced.length >= MAX_PENDING_INVITES) {
      throw new Error("Too many pending invites");
    }
    for (const invite of replaced) await ctx.db.patch(invite._id, { status: "revoked" });

    const workspace = await loadWorkspace(ctx, ownerId, WORKSPACE_ID);
    const inviteId = await ctx.db.insert("lendInvites", {
      inviterId: ownerId,
      inviterName: displayName(identity, workspace),
      inviteeId,
      ...(contactId ? { contactId } : {}),
      contactName,
      status: "pending",
    });
    return { inviteId };
  },
});

export const cancelLendInvite = mutation({
  args: { inviteId: v.id("lendInvites") },
  returns: v.null(),
  handler: async (ctx, { inviteId }) => {
    const identity = await requireIdentity(ctx);
    const invite = await ctx.db.get(inviteId);
    if (!invite || invite.inviterId !== identity.tokenIdentifier) {
      throw new Error("Invite not found");
    }
    if (invite.status === "pending") await ctx.db.patch(invite._id, { status: "revoked" });
    return null;
  },
});

/** Invites waiting for the caller to accept or decline. */
export const listIncomingLendInvites = query({
  args: {},
  returns: v.array(
    v.object({
      inviteId: v.id("lendInvites"),
      inviterName: v.string(),
      inviterEmail: v.optional(v.string()),
      inviterPhotoUrl: v.optional(v.string()),
      /** Turns a stopped share back on; accepting needs no merge choice. */
      reconnect: v.boolean(),
      createdAt: v.number(),
    }),
  ),
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const invites = await ctx.db
      .query("lendInvites")
      .withIndex("by_inviteeId_and_status", (q) =>
        q.eq("inviteeId", identity.tokenIdentifier).eq("status", "pending"),
      )
      .take(LIST_LIMIT);
    return await Promise.all(
      invites.map(async (invite) => {
        const inviter = await publicProfileOf(ctx, invite.inviterId);
        return {
          inviteId: invite._id,
          inviterName: invite.inviterName,
          ...(inviter.email ? { inviterEmail: inviter.email } : {}),
          ...(inviter.photoUrl ? { inviterPhotoUrl: inviter.photoUrl } : {}),
          reconnect: invite.reconnectId !== undefined,
          createdAt: invite._creationTime,
        };
      }),
    );
  },
});

/** Pending invites the caller sent, so their contacts can show "Invited". */
export const listOutgoingLendInvites = query({
  args: {},
  returns: v.array(
    v.object({
      inviteId: v.id("lendInvites"),
      contactName: v.string(),
      contactId: v.optional(v.string()),
      inviteeEmail: v.optional(v.string()),
      inviteePhotoUrl: v.optional(v.string()),
      createdAt: v.number(),
    }),
  ),
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const invites = await pendingInvitesFrom(ctx, identity.tokenIdentifier);
    return await Promise.all(
      invites.map(async (invite) => {
        const invitee = await publicProfileOf(ctx, invite.inviteeId);
        return {
          inviteId: invite._id,
          contactName: invite.contactName,
          ...(invite.contactId !== undefined ? { contactId: invite.contactId } : {}),
          ...(invitee.email ? { inviteeEmail: invitee.email } : {}),
          ...(invitee.photoUrl ? { inviteePhotoUrl: invitee.photoUrl } : {}),
          createdAt: invite._creationTime,
        };
      }),
    );
  },
});

export const declineLendInvite = mutation({
  args: { inviteId: v.id("lendInvites") },
  returns: v.null(),
  handler: async (ctx, { inviteId }) => {
    const identity = await requireIdentity(ctx);
    const invite = await ctx.db.get(inviteId);
    if (!invite || invite.inviteeId !== identity.tokenIdentifier) {
      throw new Error("Invite not found");
    }
    if (invite.status === "pending") await ctx.db.patch(invite._id, { status: "declined" });
    return null;
  },
});

export const acceptLendInvite = mutation({
  args: {
    inviteId: v.id("lendInvites"),
    /** The accepter's existing local contact for the inviter, if any. */
    contactId: v.optional(v.string()),
    /** What the accepter calls the inviter. Defaults to the inviter's name. */
    contactName: v.optional(v.string()),
    /**
     * Whose past entries make up the shared ledger when both sides already
     * tracked each other. The other side's private entries are deleted so the
     * balance is not counted twice.
     */
    history: v.union(v.literal("both"), v.literal("inviter"), v.literal("accepter")),
  },
  returns: v.object({
    connectionId: v.id("lendConnections"),
    contactId: v.string(),
  }),
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const ownerId = identity.tokenIdentifier;
    const invite = await ctx.db.get(args.inviteId);
    if (!invite || invite.inviteeId !== ownerId) throw new Error("Invite not found");
    if (invite.status !== "pending") throw new Error("Invite is no longer valid");
    if (await findConnectionBetween(ctx, invite.inviterId, ownerId)) {
      throw new Error("You already share with this person");
    }
    if (invite.reconnectId) return await reconnect(ctx, invite, ownerId);
    const contactId = args.contactId?.trim() || undefined;
    if (contactId?.startsWith(SHARED_CONTACT_PREFIX)) {
      throw new Error("This contact is already shared");
    }

    // Each side sees the other under their Dimo account name, replacing
    // whatever the inviter had typed for them.
    const accepterName = (await loadWorkspace(ctx, ownerId, WORKSPACE_ID))?.name?.trim();
    const inviterName = (await loadWorkspace(ctx, invite.inviterId, WORKSPACE_ID))?.name?.trim();
    const connectionId = await ctx.db.insert("lendConnections", {
      memberA: invite.inviterId,
      memberB: ownerId,
      contactNameForA: accepterName || identity.name?.trim() || invite.contactName,
      contactNameForB: inviterName || invite.inviterName || cleanName(args.contactName),
      status: "active",
      createdAt: Date.now(),
    });
    await ctx.db.patch(invite._id, { status: "accepted", connectionId });
    // Any invite the accepter had sent the other way is now moot.
    const reverse = await pendingInviteBetween(ctx, ownerId, invite.inviterId);
    if (reverse) await ctx.db.patch(reverse._id, { status: "revoked" });

    const jobs: Array<{ ownerId: string; contactId: string; mode: "share" | "discard" }> = [];
    if (invite.contactId) {
      jobs.push({
        ownerId: invite.inviterId,
        contactId: invite.contactId,
        mode: args.history === "accepter" ? "discard" : "share",
      });
    }
    if (contactId) {
      jobs.push({
        ownerId,
        contactId,
        mode: args.history === "inviter" ? "discard" : "share",
      });
    }
    for (const job of jobs) {
      await ctx.scheduler.runAfter(0, linkLendHistoryRef, { connectionId, ...job });
    }
    return { connectionId, contactId: sharedContactId(connectionId) };
  },
});

/**
 * Moves one member's private history with a contact into the shared ledger,
 * or deletes it when the other side's history was chosen. Runs in batches;
 * converted rows leave the contact's index range so each batch makes progress.
 */
export const linkLendHistory = internalMutation({
  args: {
    connectionId: v.id("lendConnections"),
    ownerId: v.string(),
    contactId: v.string(),
    mode: v.union(v.literal("share"), v.literal("discard")),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const connection = await ctx.db.get(args.connectionId);
    if (!connection || connection.status !== "active" || !isMember(connection, args.ownerId)) {
      return null;
    }
    const rows = await ctx.db
      .query("lends")
      .withIndex("by_owner_workspace_contactId_deleted", (q) =>
        q
          .eq("ownerId", args.ownerId)
          .eq("workspaceId", WORKSPACE_ID)
          .eq("contactId", args.contactId)
          .eq("deleted", false),
      )
      .take(LINK_BATCH_SIZE);

    const now = Date.now();
    const revisions = new RevisionBook(ctx);
    const fallbackCurrency = await preferredCurrency(ctx, args.ownerId);
    for (const row of rows) {
      const version = serverVersion(row.version, now);
      if (args.mode === "discard") {
        await ctx.db.patch(row._id, {
          version,
          deleted: true,
          revision: await revisions.next(args.ownerId),
        });
        continue;
      }
      const existing = await findSharedLend(ctx, connection._id, row.entityId);
      const next = {
        connectionId: connection._id,
        entityId: row.entityId,
        version,
        deleted: false,
        amountMinor: row.amountMinor,
        currency: row.currency ?? fallbackCurrency,
        occurredAt: row.occurredAt,
        comment: row.comment,
        kindForA: kindBetween(connection, args.ownerId, row.kind ?? "lent"),
        authorId: args.ownerId,
        lastEditorId: args.ownerId,
      };
      await upsertShared(ctx, existing, next);
      await writeProjection(ctx, revisions, connection, next, args.ownerId, {
        allowConvertingPrivateRow: true,
      });
      await writeProjection(ctx, revisions, connection, next, otherMember(connection, args.ownerId), {
        allowConvertingPrivateRow: false,
      });
    }
    await revisions.flush();
    if (rows.length === LINK_BATCH_SIZE) {
      await ctx.scheduler.runAfter(0, linkLendHistoryRef, args);
    }
    return null;
  },
});

/** Deletes a revoked connection's authoritative copies in batches. */
export const purgeSharedLends = internalMutation({
  args: { connectionId: v.id("lendConnections") },
  returns: v.null(),
  handler: async (ctx, { connectionId }) => {
    // Shared again before the purge finished: the copies are live again.
    if ((await ctx.db.get(connectionId))?.status === "active") return null;
    const rows = await ctx.db
      .query("sharedLends")
      .withIndex("by_connectionId_and_entityId", (q) => q.eq("connectionId", connectionId))
      .take(LINK_BATCH_SIZE);
    for (const row of rows) await ctx.db.delete(row._id);
    if (rows.length === LINK_BATCH_SIZE) {
      await ctx.scheduler.runAfter(0, purgeSharedLendsRef, { connectionId });
    }
    return null;
  },
});

const connectionSummaryValidator = v.object({
  connectionId: v.id("lendConnections"),
  contactId: v.string(),
  contactName: v.string(),
  status: v.union(v.literal("active"), v.literal("revoked")),
  createdAt: v.number(),
  revokedAt: v.optional(v.number()),
  /** The other member's profile photo. */
  photoUrl: v.optional(v.string()),
});

export const listLendConnections = query({
  args: {},
  returns: v.array(connectionSummaryValidator),
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const ownerId = identity.tokenIdentifier;
    const asA = await ctx.db
      .query("lendConnections")
      .withIndex("by_memberA_and_memberB", (q) => q.eq("memberA", ownerId))
      .take(LIST_LIMIT);
    const asB = await ctx.db
      .query("lendConnections")
      .withIndex("by_memberB_and_memberA", (q) => q.eq("memberB", ownerId))
      .take(LIST_LIMIT);
    const connections = [...asA, ...asB].sort((a, b) => b.createdAt - a.createdAt);
    return await Promise.all(
      connections.map(async (connection) => {
        const other = await publicProfileOf(ctx, otherMember(connection, ownerId));
        return {
          connectionId: connection._id,
          contactId: sharedContactId(connection._id),
          contactName: contactNameFor(connection, ownerId),
          status: connection.status,
          createdAt: connection.createdAt,
          ...(connection.revokedAt !== undefined ? { revokedAt: connection.revokedAt } : {}),
          ...(other.photoUrl ? { photoUrl: other.photoUrl } : {}),
        };
      }),
    );
  },
});

/** Stops sharing. Both members keep their copies as private history. */
export const revokeLendConnection = mutation({
  args: { connectionId: v.id("lendConnections") },
  returns: v.null(),
  handler: async (ctx, { connectionId }) => {
    const identity = await requireIdentity(ctx);
    const connection = await ctx.db.get(connectionId);
    if (!connection || !isMember(connection, identity.tokenIdentifier)) {
      throw new Error("Connection not found");
    }
    await revokeConnection(ctx, connection);
    return null;
  },
});

/**
 * Invites the other member of a stopped connection to share again. Accepting
 * turns the same connection back on, so both sides' history lines up again.
 */
export const reshareLendConnection = mutation({
  args: { connectionId: v.id("lendConnections") },
  returns: v.object({ inviteId: v.id("lendInvites") }),
  handler: async (ctx, { connectionId }) => {
    const identity = await requireIdentity(ctx);
    const ownerId = identity.tokenIdentifier;
    const connection = await ctx.db.get(connectionId);
    if (!connection || !isMember(connection, ownerId)) throw new Error("Connection not found");
    const other = otherMember(connection, ownerId);
    if (connection.status === "active" || (await findConnectionBetween(ctx, ownerId, other))) {
      throw new Error("You already share with this person");
    }
    if (await pendingInviteBetween(ctx, other, ownerId)) {
      throw new Error("They already invited you. Accept their invite in Lending");
    }
    const pending = await pendingInvitesFrom(ctx, ownerId);
    const replaced = pending.filter((invite) => invite.inviteeId === other);
    if (pending.length - replaced.length >= MAX_PENDING_INVITES) {
      throw new Error("Too many pending invites");
    }
    for (const invite of replaced) await ctx.db.patch(invite._id, { status: "revoked" });

    const workspace = await loadWorkspace(ctx, ownerId, WORKSPACE_ID);
    const inviteId = await ctx.db.insert("lendInvites", {
      inviterId: ownerId,
      inviterName: displayName(identity, workspace),
      inviteeId: other,
      contactId: sharedContactId(connection._id),
      contactName: contactNameFor(connection, ownerId),
      status: "pending",
      reconnectId: connection._id,
    });
    return { inviteId };
  },
});

async function accountName(ctx: QueryCtx, ownerId: string) {
  return (await loadWorkspace(ctx, ownerId, WORKSPACE_ID))?.name?.trim() || undefined;
}

/** Accepts an invite to share a stopped connection again. */
async function reconnect(ctx: MutationCtx, invite: Doc<"lendInvites">, ownerId: string) {
  const connection = invite.reconnectId ? await ctx.db.get(invite.reconnectId) : null;
  if (
    !connection ||
    connection.status === "active" ||
    !isMember(connection, ownerId) ||
    !isMember(connection, invite.inviterId)
  ) {
    throw new Error("Invite is no longer valid");
  }
  const nameA = await accountName(ctx, connection.memberA);
  const nameB = await accountName(ctx, connection.memberB);
  await ctx.db.patch(connection._id, {
    status: "active",
    revokedAt: undefined,
    // Each side sees the other under their current account name.
    ...(nameB ? { contactNameForA: nameB } : {}),
    ...(nameA ? { contactNameForB: nameA } : {}),
  });
  await ctx.db.patch(invite._id, { status: "accepted", connectionId: connection._id });
  const reverse = await pendingInviteBetween(ctx, ownerId, invite.inviterId);
  if (reverse) await ctx.db.patch(reverse._id, { status: "revoked" });
  await ctx.scheduler.runAfter(0, relinkLendHistoryRef, {
    connectionId: connection._id,
    member: "a",
    cursor: null,
  });
  return { connectionId: connection._id, contactId: sharedContactId(connection._id) };
}

/**
 * Re-merges both members' copies after a connection is turned back on. While
 * it was stopped either side may have added, edited or deleted entries, so
 * each entry keeps its newest version (deletes included) and is mirrored to
 * the other member. Pages through member A's entries, then member B's.
 */
export const relinkLendHistory = internalMutation({
  args: {
    connectionId: v.id("lendConnections"),
    member: v.union(v.literal("a"), v.literal("b")),
    cursor: v.union(v.string(), v.null()),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const connection = await ctx.db.get(args.connectionId);
    if (!connection || connection.status !== "active") return null;
    const ownerId = args.member === "a" ? connection.memberA : connection.memberB;
    const other = otherMember(connection, ownerId);
    const contactId = sharedContactId(connection._id);
    const page = await ctx.db
      .query("lends")
      .withIndex("by_owner_workspace_contactId_deleted", (q) =>
        q.eq("ownerId", ownerId).eq("workspaceId", WORKSPACE_ID).eq("contactId", contactId),
      )
      .paginate({ numItems: LINK_BATCH_SIZE, cursor: args.cursor });

    const revisions = new RevisionBook(ctx);
    for (const row of page.page) {
      const shared = await findSharedLend(ctx, connection._id, row.entityId);
      if (shared && compareVersions(row.version, shared.version) <= 0) {
        // The other side's copy is newer; bring this one up to date.
        if (compareVersions(shared.version, row.version) > 0) {
          await writeProjection(ctx, revisions, connection, shared, ownerId, {
            allowConvertingPrivateRow: true,
          });
        }
        continue;
      }
      const next = {
        connectionId: connection._id,
        entityId: row.entityId,
        version: row.version,
        deleted: row.deleted,
        amountMinor: row.amountMinor,
        ...((row.currency ?? shared?.currency) !== undefined
          ? { currency: row.currency ?? shared?.currency }
          : {}),
        occurredAt: row.occurredAt,
        comment: row.comment,
        kindForA: kindBetween(connection, ownerId, row.kind ?? "lent"),
        authorId: shared?.authorId ?? (row.createdBy === "contact" ? other : ownerId),
        lastEditorId: row.lastEditedBy === "contact" ? other : ownerId,
      };
      await upsertShared(ctx, shared, next);
      await writeProjection(ctx, revisions, connection, next, ownerId, {
        allowConvertingPrivateRow: true,
      });
      // Never overwrite an unrelated entry of theirs that happens to share the id.
      const theirs = await findLendRow(ctx, other, row.entityId);
      if (!theirs || theirs.contactId === contactId) {
        await writeProjection(ctx, revisions, connection, next, other, {
          allowConvertingPrivateRow: true,
        });
      }
    }
    await revisions.flush();

    if (!page.isDone) {
      await ctx.scheduler.runAfter(0, relinkLendHistoryRef, {
        connectionId: args.connectionId,
        member: args.member,
        cursor: page.continueCursor,
      });
    } else if (args.member === "a") {
      await ctx.scheduler.runAfter(0, relinkLendHistoryRef, {
        connectionId: args.connectionId,
        member: "b",
        cursor: null,
      });
    }
    return null;
  },
});
