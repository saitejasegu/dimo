/**
 * Typed-table sync helpers shared by per-type push/pull and server writers.
 */
/* eslint-disable @typescript-eslint/no-explicit-any */

import type { EntityTypeName } from "./values";
import { TYPED_TABLE_BY_ENTITY } from "./values";

export type Version = { timestamp: number; counter: number; deviceId: string };

export type TypedSyncRow = {
  _id?: any;
  ownerId?: string;
  workspaceId: string;
  entityId: string;
  version: Version;
  deleted: boolean;
  revision: number;
  [field: string]: unknown;
};

export function compareVersions(a: Version, b: Version) {
  if (a.timestamp !== b.timestamp) return a.timestamp - b.timestamp;
  if (a.counter !== b.counter) return a.counter - b.counter;
  return a.deviceId.localeCompare(b.deviceId);
}

export function typedTableFor(entityType: EntityTypeName) {
  return TYPED_TABLE_BY_ENTITY[entityType];
}

/** Rebuild a nested payload from a typed row (entityId → id). Useful for tests. */
export function payloadFromTyped(
  entityType: EntityTypeName,
  row: TypedSyncRow,
): Record<string, unknown> {
  void entityType;
  const fields: Record<string, unknown> = { ...row };
  const entityId = String(fields.entityId);
  delete fields._id;
  delete fields.ownerId;
  delete fields.workspaceId;
  delete fields.entityId;
  delete fields.version;
  delete fields.deleted;
  delete fields.revision;
  return { id: entityId, ...fields };
}

/** Flatten a nested payload into typed column fields (drop nested id). */
export function typedFieldsFromPayload(
  payload: Record<string, unknown>,
): Record<string, unknown> {
  const fields = { ...payload };
  delete fields.id;
  return fields;
}

async function findTyped(
  ctx: { db: any },
  table: string,
  ownerId: string,
  workspaceId: string,
  entityId: string,
) {
  return await ctx.db
    .query(table)
    .withIndex("by_owner_workspace_entity", (q: any) =>
      q.eq("ownerId", ownerId).eq("workspaceId", workspaceId).eq("entityId", entityId),
    )
    .unique();
}

/** Upsert a typed row (LWW already decided). */
export async function writeTyped(
  ctx: { db: any },
  entityType: EntityTypeName,
  typedRow: TypedSyncRow,
) {
  const ownerId = typedRow.ownerId;
  if (!ownerId) throw new Error("ownerId required");
  const table = typedTableFor(entityType);
  const current = await findTyped(
    ctx,
    table,
    ownerId,
    typedRow.workspaceId,
    typedRow.entityId,
  );
  const value = { ...typedRow };
  delete value._id;
  if (current) await ctx.db.replace(current._id, value);
  else await ctx.db.insert(table, value);
  return value as TypedSyncRow;
}

export async function getTypedRow(
  ctx: { db: any },
  entityType: EntityTypeName,
  ownerId: string,
  workspaceId: string,
  entityId: string,
) {
  return await findTyped(
    ctx,
    typedTableFor(entityType),
    ownerId,
    workspaceId,
    entityId,
  );
}

/** Clear up to `take` rows of one entity type from its typed table. */
export async function clearEntityType(
  ctx: { db: any },
  ownerId: string,
  workspaceId: string,
  entityType: EntityTypeName,
  take: number,
): Promise<{ deleted: number; exhausted: boolean }> {
  if (take <= 0) return { deleted: 0, exhausted: false };
  const table = typedTableFor(entityType);
  const typedRows = await ctx.db
    .query(table)
    .withIndex("by_owner_workspace_entity", (q: any) =>
      q.eq("ownerId", ownerId).eq("workspaceId", workspaceId),
    )
    .take(take);
  for (const row of typedRows) {
    await ctx.db.delete(row._id);
  }
  const more = await ctx.db
    .query(table)
    .withIndex("by_owner_workspace_entity", (q: any) =>
      q.eq("ownerId", ownerId).eq("workspaceId", workspaceId),
    )
    .first();
  return { deleted: typedRows.length, exhausted: !more };
}

/** True if the owner still has any row in any typed entity table. */
export async function hasAnyTypedEntity(
  ctx: { db: any },
  ownerId: string,
  workspaceId: string,
): Promise<boolean> {
  for (const table of Object.values(TYPED_TABLE_BY_ENTITY)) {
    const row = await ctx.db
      .query(table)
      .withIndex("by_owner_workspace_entity", (q: any) =>
        q.eq("ownerId", ownerId).eq("workspaceId", workspaceId),
      )
      .first();
    if (row) return true;
  }
  return false;
}
