import { mutationGeneric, queryGeneric } from "convex/server";
import { v } from "convex/values";
import { entityTypeValidator, operationValidator } from "./values";

/* Generic Convex functions intentionally use untyped index builders until a
   deployment is linked and Convex generates its schema-specific bindings. */
/* eslint-disable @typescript-eslint/no-explicit-any */

type Version = { timestamp: number; counter: number; deviceId: string };

async function requireOwnerId(ctx: { auth: { getUserIdentity(): Promise<{ tokenIdentifier: string } | null> } }) {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) throw new Error("Not authenticated");
  return identity.tokenIdentifier;
}

function compareVersions(a: Version, b: Version) {
  if (a.timestamp !== b.timestamp) return a.timestamp - b.timestamp;
  if (a.counter !== b.counter) return a.counter - b.counter;
  return a.deviceId.localeCompare(b.deviceId);
}

function payloadMatches(type: string, payload: Record<string, unknown>) {
  switch (type) {
    case "category":
      return "monthlyBudgetMinor" in payload;
    case "paymentMethod":
      return "archived" in payload && "type" in payload;
    case "transaction":
      return "occurredAt" in payload;
    case "recurring":
      return "anchorDate" in payload && "frequency" in payload;
    case "lend":
      return "contactName" in payload && "occurredAt" in payload;
    case "preferences":
      return payload.id === "preferences";
    default:
      return false;
  }
}

export const push = mutationGeneric({
  args: {
    workspaceId: v.string(),
    operations: v.array(operationValidator),
  },
  handler: async (ctx, { workspaceId, operations }) => {
    const ownerId = await requireOwnerId(ctx);
    if (workspaceId !== "global") throw new Error("Unsupported workspace");
    if (operations.length > 50) throw new Error("A push may contain at most 50 operations");

    let workspace = await ctx.db
      .query("workspaces")
      .withIndex("by_owner_and_workspace", (q: any) =>
        q.eq("ownerId", ownerId).eq("workspaceId", workspaceId),
      )
      .unique();
    let revision = workspace?.revision ?? 0;
    const acknowledgements: Array<{
      operationId: string;
      applied: boolean;
      revision: number;
    }> = [];

    for (const operation of operations) {
      if (operation.workspaceId !== workspaceId) throw new Error("Workspace mismatch");
      if (operation.entityId !== operation.payload.id) throw new Error("Entity ID mismatch");
      if (!payloadMatches(operation.entityType, operation.payload)) {
        throw new Error(`Payload does not match ${operation.entityType}`);
      }
      if (!Number.isInteger(operation.version.timestamp) || !Number.isInteger(operation.version.counter)) {
        throw new Error("Invalid logical version");
      }
      const untypedPayload = operation.payload as Record<string, unknown>;
      if (
        (operation.entityType === "transaction" ||
          operation.entityType === "recurring" ||
          operation.entityType === "lend") &&
        (!Number.isInteger(untypedPayload.amountMinor) || Number(untypedPayload.amountMinor) <= 0)
      ) {
        throw new Error("Invalid minor-unit amount");
      }
      if (
        operation.entityType === "recurring" &&
        !/^\d{4}-\d{2}-\d{2}$/.test(String(untypedPayload.anchorDate))
      ) {
        throw new Error("Invalid recurring anchor date");
      }

      const current = await ctx.db
        .query("entities")
        .withIndex("by_owner_and_workspace_and_entity", (q: any) =>
          q
            .eq("ownerId", ownerId)
            .eq("workspaceId", workspaceId)
            .eq("entityType", operation.entityType)
            .eq("entityId", operation.entityId),
        )
        .unique();
      const applied = !current || compareVersions(operation.version, current.version) > 0;
      if (applied) {
        revision += 1;
        const value = {
          ownerId,
          workspaceId,
          entityType: operation.entityType,
          entityId: operation.entityId,
          version: operation.version,
          payload: operation.payload,
          deleted: operation.deleted,
          revision,
        };
        if (current) await ctx.db.replace(current._id, value);
        else await ctx.db.insert("entities", value);
      }
      acknowledgements.push({
        operationId: operation.operationId,
        applied,
        revision: applied ? revision : (current?.revision ?? revision),
      });
    }

    if (!workspace) {
      const id = await ctx.db.insert("workspaces", { ownerId, workspaceId, revision });
      workspace = await ctx.db.get(id);
    } else if (workspace.revision !== revision) {
      await ctx.db.patch(workspace._id, { revision });
    }
    return { acknowledgements, latestRevision: revision };
  },
});

export const pull = queryGeneric({
  args: {
    workspaceId: v.string(),
    afterRevision: v.number(),
    limit: v.number(),
  },
  handler: async (ctx, { workspaceId, afterRevision, limit }) => {
    const ownerId = await requireOwnerId(ctx);
    if (workspaceId !== "global") throw new Error("Unsupported workspace");
    const take = Math.max(1, Math.min(200, Math.floor(limit)));
    const rows = await ctx.db
      .query("entities")
      .withIndex("by_owner_and_workspace_and_revision", (q: any) =>
        q
          .eq("ownerId", ownerId)
          .eq("workspaceId", workspaceId)
          .gt("revision", afterRevision),
      )
      .take(take + 1);
    const entities = rows.slice(0, take).map((row) => ({
      workspaceId: row.workspaceId,
      entityType: row.entityType,
      entityId: row.entityId,
      version: row.version,
      payload: row.payload,
      deleted: row.deleted,
      serverRevision: row.revision,
    }));
    const workspace = await ctx.db
      .query("workspaces")
      .withIndex("by_owner_and_workspace", (q: any) =>
        q.eq("ownerId", ownerId).eq("workspaceId", workspaceId),
      )
      .unique();
    return {
      entities,
      latestRevision: workspace?.revision ?? 0,
      hasMore: rows.length > take,
    };
  },
});

export const currentRevision = queryGeneric({
  args: { workspaceId: v.string() },
  handler: async (ctx, { workspaceId }) => {
    const ownerId = await requireOwnerId(ctx);
    if (workspaceId !== "global") throw new Error("Unsupported workspace");
    const workspace = await ctx.db
      .query("workspaces")
      .withIndex("by_owner_and_workspace", (q: any) =>
        q.eq("ownerId", ownerId).eq("workspaceId", workspaceId),
      )
      .unique();
    return workspace?.revision ?? 0;
  },
});

/**
 * Hard-deletes owner-scoped entities for the given types (paged) so Sync now can
 * re-upload that app's local snapshot without wiping other apps' entity types.
 */
export const clearWorkspace = mutationGeneric({
  args: {
    workspaceId: v.string(),
    entityTypes: v.array(entityTypeValidator),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, { workspaceId, entityTypes, limit }) => {
    const ownerId = await requireOwnerId(ctx);
    if (workspaceId !== "global") throw new Error("Unsupported workspace");
    const types = [...new Set(entityTypes)];
    if (types.length === 0) throw new Error("entityTypes must not be empty");
    const take = Math.max(1, Math.min(200, Math.floor(limit ?? 100)));

    let deleted = 0;
    let hasMore = false;
    for (const entityType of types) {
      const remaining = take - deleted;
      if (remaining <= 0) {
        hasMore = true;
        break;
      }
      const rows = await ctx.db
        .query("entities")
        .withIndex("by_owner_and_workspace_and_entity", (q: any) =>
          q
            .eq("ownerId", ownerId)
            .eq("workspaceId", workspaceId)
            .eq("entityType", entityType),
        )
        .take(remaining);
      for (const row of rows) {
        await ctx.db.delete(row._id);
      }
      deleted += rows.length;
      if (rows.length === remaining) {
        hasMore = true;
        break;
      }
    }

    if (!hasMore) {
      const leftover = await ctx.db
        .query("entities")
        .withIndex("by_owner_and_workspace_and_revision", (q: any) =>
          q.eq("ownerId", ownerId).eq("workspaceId", workspaceId),
        )
        .first();
      if (!leftover) {
        const workspace = await ctx.db
          .query("workspaces")
          .withIndex("by_owner_and_workspace", (q: any) =>
            q.eq("ownerId", ownerId).eq("workspaceId", workspaceId),
          )
          .unique();
        if (workspace && workspace.revision !== 0) {
          await ctx.db.patch(workspace._id, { revision: 0 });
        }
      }
    }
    return { deleted, hasMore };
  },
});
