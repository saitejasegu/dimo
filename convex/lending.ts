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
const INVITE_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const MAX_PENDING_INVITES = 20;
const INVITE_CODE_LENGTH = 10;
/** No 0/O, 1/I/L so codes survive being read aloud or retyped. */
const INVITE_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
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

function generateInviteCode() {
  const bytes = new Uint8Array(INVITE_CODE_LENGTH);
  crypto.getRandomValues(bytes);
  let code = "";
  for (const byte of bytes) code += INVITE_CODE_ALPHABET[byte % INVITE_CODE_ALPHABET.length];
  return code;
}

function normalizeInviteCode(code: string) {
  return code.trim().toUpperCase().replace(/[^A-Z0-9]/g, "");
}

function displayName(identity: AuthIdentity, workspace: Doc<"workspaces"> | null) {
  return workspace?.name?.trim() || identity.name?.trim() || "Dimo user";
}

async function findInvite(ctx: QueryCtx, code: string) {
  return await ctx.db
    .query("lendInvites")
    .withIndex("by_code", (q) => q.eq("code", normalizeInviteCode(code)))
    .unique();
}

async function insertInvite(
  ctx: MutationCtx,
  identity: AuthIdentity,
  args: { contactId?: string; contactName: string; inviteeId?: string },
) {
  const ownerId = identity.tokenIdentifier;
  const contactName = cleanName(args.contactName);
  if (!contactName) throw new Error("Contact name is required");
  const contactId = args.contactId?.trim() || undefined;
  if (contactId?.startsWith(SHARED_CONTACT_PREFIX)) {
    throw new Error("This contact is already shared");
  }

  const now = Date.now();
  const pending = await ctx.db
    .query("lendInvites")
    .withIndex("by_inviterId_and_status", (q) =>
      q.eq("inviterId", ownerId).eq("status", "pending"),
    )
    .take(MAX_PENDING_INVITES * 2);
  const live = pending.filter((invite) => invite.expiresAt > now);
  // An invite for the same contact replaces the older one.
  const replaced = live.filter((invite) => contactId && invite.contactId === contactId);
  if (live.length - replaced.length >= MAX_PENDING_INVITES) {
    throw new Error("Too many pending invites");
  }
  for (const invite of replaced) await ctx.db.patch(invite._id, { status: "revoked" });

  let code = generateInviteCode();
  while (await findInvite(ctx, code)) code = generateInviteCode();
  const workspace = await loadWorkspace(ctx, ownerId, WORKSPACE_ID);
  const expiresAt = now + INVITE_TTL_MS;
  await ctx.db.insert("lendInvites", {
    code,
    inviterId: ownerId,
    inviterName: displayName(identity, workspace),
    ...(contactId ? { contactId } : {}),
    contactName,
    status: "pending",
    expiresAt,
    ...(args.inviteeId ? { inviteeId: args.inviteeId } : {}),
  });
  return { code, expiresAt };
}

const inviteResultValidator = v.object({ code: v.string(), expiresAt: v.number() });

export const createLendInvite = mutation({
  args: {
    /** The inviter's local contact whose history is shared once accepted. */
    contactId: v.optional(v.string()),
    /** What the inviter calls the person being invited. */
    contactName: v.string(),
  },
  returns: inviteResultValidator,
  handler: async (ctx, args) => insertInvite(ctx, await requireIdentity(ctx), args),
});

export function normalizeEmail(email: string) {
  return email.trim().toLowerCase();
}

/**
 * Addresses an invite to whoever has verified `email`. The response is the
 * same whether or not that address belongs to a Dimo account, so the endpoint
 * cannot be used to discover who uses Dimo; the returned code can still be
 * shared as a link.
 */
export const inviteLendContactByEmail = mutation({
  args: {
    email: v.string(),
    contactId: v.optional(v.string()),
    contactName: v.string(),
  },
  returns: inviteResultValidator,
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const email = normalizeEmail(args.email);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) {
      throw new Error("Enter a valid email address");
    }
    const account = await ctx.db
      .query("accountEmails")
      .withIndex("by_email", (q) => q.eq("email", email))
      .first();
    const inviteeId =
      account && account.ownerId !== identity.tokenIdentifier ? account.ownerId : undefined;
    return await insertInvite(ctx, identity, {
      contactId: args.contactId,
      contactName: args.contactName,
      inviteeId,
    });
  },
});

export const cancelLendInvite = mutation({
  args: { code: v.string() },
  returns: v.null(),
  handler: async (ctx, { code }) => {
    const identity = await requireIdentity(ctx);
    const invite = await findInvite(ctx, code);
    if (!invite || invite.inviterId !== identity.tokenIdentifier) {
      throw new Error("Invite not found");
    }
    if (invite.status === "pending") await ctx.db.patch(invite._id, { status: "revoked" });
    return null;
  },
});

/** What the invitee sees before accepting. Expiry is enforced on accept. */
export const previewLendInvite = query({
  args: { code: v.string() },
  returns: v.union(
    v.null(),
    v.object({
      inviterName: v.string(),
      status: v.union(v.literal("pending"), v.literal("accepted"), v.literal("revoked")),
      expiresAt: v.number(),
      isOwnInvite: v.boolean(),
    }),
  ),
  handler: async (ctx, { code }) => {
    const identity = await requireIdentity(ctx);
    const invite = await findInvite(ctx, code);
    if (!invite) return null;
    return {
      inviterName: invite.inviterName,
      status: invite.status,
      expiresAt: invite.expiresAt,
      isOwnInvite: invite.inviterId === identity.tokenIdentifier,
    };
  },
});

const invitePreviewValidator = v.object({
  code: v.string(),
  inviterName: v.string(),
  expiresAt: v.number(),
});

/** Invites addressed to the caller by email. Callers filter out expired ones. */
export const listIncomingLendInvites = query({
  args: {},
  returns: v.array(invitePreviewValidator),
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const invites = await ctx.db
      .query("lendInvites")
      .withIndex("by_inviteeId_and_status", (q) =>
        q.eq("inviteeId", identity.tokenIdentifier).eq("status", "pending"),
      )
      .take(LIST_LIMIT);
    return invites.map((invite) => ({
      code: invite.code,
      inviterName: invite.inviterName,
      expiresAt: invite.expiresAt,
    }));
  },
});

/** Pending invites the caller sent, so a contact can show "Invite pending". */
export const listOutgoingLendInvites = query({
  args: {},
  returns: v.array(
    v.object({
      code: v.string(),
      contactName: v.string(),
      contactId: v.optional(v.string()),
      expiresAt: v.number(),
    }),
  ),
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const invites = await ctx.db
      .query("lendInvites")
      .withIndex("by_inviterId_and_status", (q) =>
        q.eq("inviterId", identity.tokenIdentifier).eq("status", "pending"),
      )
      .take(MAX_PENDING_INVITES * 2);
    return invites.map((invite) => ({
      code: invite.code,
      contactName: invite.contactName,
      ...(invite.contactId !== undefined ? { contactId: invite.contactId } : {}),
      expiresAt: invite.expiresAt,
    }));
  },
});

export const declineLendInvite = mutation({
  args: { code: v.string() },
  returns: v.null(),
  handler: async (ctx, { code }) => {
    const identity = await requireIdentity(ctx);
    const invite = await findInvite(ctx, code);
    if (!invite || invite.inviteeId !== identity.tokenIdentifier) {
      throw new Error("Invite not found");
    }
    if (invite.status === "pending") await ctx.db.patch(invite._id, { status: "revoked" });
    return null;
  },
});

/** Records the caller's verified email. Only `refreshVerifiedEmail` calls this,
 * with an owner and address it read from WorkOS itself. */
export const storeVerifiedEmail = internalMutation({
  args: { ownerId: v.string(), email: v.string() },
  returns: v.null(),
  handler: async (ctx, { ownerId, email }) => {
    const normalized = normalizeEmail(email);
    const existing = await ctx.db
      .query("accountEmails")
      .withIndex("by_ownerId", (q) => q.eq("ownerId", ownerId))
      .unique();
    if (existing) {
      if (existing.email !== normalized) {
        await ctx.db.patch(existing._id, { email: normalized, verifiedAt: Date.now() });
      }
    } else {
      await ctx.db.insert("accountEmails", { ownerId, email: normalized, verifiedAt: Date.now() });
    }
    return null;
  },
});

export const acceptLendInvite = mutation({
  args: {
    code: v.string(),
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
    const invite = await findInvite(ctx, args.code);
    if (!invite || invite.status !== "pending" || invite.expiresAt <= Date.now()) {
      throw new Error("Invite is no longer valid");
    }
    if (invite.inviterId === ownerId) throw new Error("You cannot accept your own invite");
    if (invite.inviteeId && invite.inviteeId !== ownerId) {
      throw new Error("This invite was sent to someone else");
    }
    if (await findConnectionBetween(ctx, invite.inviterId, ownerId)) {
      throw new Error("You already share a ledger with this person");
    }
    const contactId = args.contactId?.trim() || undefined;
    if (contactId?.startsWith(SHARED_CONTACT_PREFIX)) {
      throw new Error("This contact is already shared");
    }

    const connectionId = await ctx.db.insert("lendConnections", {
      memberA: invite.inviterId,
      memberB: ownerId,
      contactNameForA: invite.contactName,
      contactNameForB: cleanName(args.contactName) || invite.inviterName,
      status: "active",
      createdAt: Date.now(),
    });
    await ctx.db.patch(invite._id, {
      status: "accepted",
      acceptedBy: ownerId,
      connectionId,
    });

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
    return [...asA, ...asB]
      .sort((a, b) => b.createdAt - a.createdAt)
      .map((connection) => ({
        connectionId: connection._id,
        contactId: sharedContactId(connection._id),
        contactName: contactNameFor(connection, ownerId),
        status: connection.status,
        createdAt: connection.createdAt,
        ...(connection.revokedAt !== undefined ? { revokedAt: connection.revokedAt } : {}),
      }));
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
