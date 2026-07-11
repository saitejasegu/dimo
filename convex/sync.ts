import { mutationGeneric, queryGeneric } from "convex/server";
import { v } from "convex/values";
import { operationValidator } from "./values";

/* Generic Convex functions intentionally use untyped index builders until a
   deployment is linked and Convex generates its schema-specific bindings. */
/* eslint-disable @typescript-eslint/no-explicit-any */

type Version = { timestamp: number; counter: number; deviceId: string };

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
    if (workspaceId !== "global") throw new Error("Unsupported workspace");
    if (operations.length > 50) throw new Error("A push may contain at most 50 operations");

    let workspace = await ctx.db
      .query("workspaces")
      .withIndex("by_workspace", (q: any) => q.eq("workspaceId", workspaceId))
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
        (operation.entityType === "transaction" || operation.entityType === "recurring") &&
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
        .withIndex("by_workspace_entity", (q: any) =>
          q
            .eq("workspaceId", workspaceId)
            .eq("entityType", operation.entityType)
            .eq("entityId", operation.entityId),
        )
        .unique();
      const applied = !current || compareVersions(operation.version, current.version) > 0;
      if (applied) {
        revision += 1;
        const value = {
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
      const id = await ctx.db.insert("workspaces", { workspaceId, revision });
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
    const take = Math.max(1, Math.min(200, Math.floor(limit)));
    const rows = await ctx.db
      .query("entities")
      .withIndex("by_workspace_revision", (q: any) =>
        q.eq("workspaceId", workspaceId).gt("revision", afterRevision),
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
      .withIndex("by_workspace", (q: any) => q.eq("workspaceId", workspaceId))
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
    const workspace = await ctx.db
      .query("workspaces")
      .withIndex("by_workspace", (q: any) => q.eq("workspaceId", workspaceId))
      .unique();
    return workspace?.revision ?? 0;
  },
});
