/**
 * Dual-write bridge between typed per-entity tables and the legacy blob
 * `entities` table. Deleted wholesale at narrow time once Android migrates.
 */
/* eslint-disable @typescript-eslint/no-explicit-any */

import type { EntityTypeName } from "./values";
import { TYPED_TABLE_BY_ENTITY } from "./values";

export type Version = { timestamp: number; counter: number; deviceId: string };

export type BlobEntity = {
  _id?: any;
  ownerId?: string;
  workspaceId: string;
  entityType: EntityTypeName;
  entityId: string;
  version: Version;
  payload: Record<string, unknown>;
  deleted: boolean;
  revision: number;
};

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

/** Rebuild the legacy nested payload from a typed row (entityId → id). */
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

/** Flatten a blob payload into typed column fields (drop nested id). */
export function typedFieldsFromPayload(
  payload: Record<string, unknown>,
): Record<string, unknown> {
  const fields = { ...payload };
  delete fields.id;
  return fields;
}

async function findBlob(
  ctx: { db: any },
  ownerId: string,
  workspaceId: string,
  entityType: EntityTypeName,
  entityId: string,
) {
  return await ctx.db
    .query("entities")
    .withIndex("by_owner_and_workspace_and_entity", (q: any) =>
      q
        .eq("ownerId", ownerId)
        .eq("workspaceId", workspaceId)
        .eq("entityType", entityType)
        .eq("entityId", entityId),
    )
    .unique();
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

/**
 * Mirror a typed row into the legacy blob `entities` table with identical
 * version / revision / deleted. Idempotent replace by owner+type+id.
 */
export async function mirrorToBlob(
  ctx: { db: any },
  entityType: EntityTypeName,
  typedRow: TypedSyncRow,
) {
  const ownerId = typedRow.ownerId;
  if (!ownerId) return;
  const payload = payloadFromTyped(entityType, typedRow);
  const value = {
    ownerId,
    workspaceId: typedRow.workspaceId,
    entityType,
    entityId: typedRow.entityId,
    version: typedRow.version,
    payload,
    deleted: typedRow.deleted,
    revision: typedRow.revision,
  };
  const current = await findBlob(
    ctx,
    ownerId,
    typedRow.workspaceId,
    entityType,
    typedRow.entityId,
  );
  if (current) await ctx.db.replace(current._id, value);
  else await ctx.db.insert("entities", value);
}

/**
 * Explode a blob push/op (or existing blob row) into the matching typed table.
 * Idempotent replace by owner+entityId.
 */
export async function mirrorToTyped(
  ctx: { db: any },
  entityType: EntityTypeName,
  blob: {
    ownerId?: string;
    workspaceId: string;
    entityId: string;
    version: Version;
    payload: Record<string, unknown>;
    deleted: boolean;
    revision: number;
  },
) {
  const ownerId = blob.ownerId;
  if (!ownerId) return;
  const table = typedTableFor(entityType);
  const fields = typedFieldsFromPayload(blob.payload as Record<string, unknown>);
  const value = {
    ownerId,
    workspaceId: blob.workspaceId,
    entityId: blob.entityId,
    version: blob.version,
    deleted: blob.deleted,
    revision: blob.revision,
    ...fields,
  };
  const current = await findTyped(
    ctx,
    table,
    ownerId,
    blob.workspaceId,
    blob.entityId,
  );
  if (current) await ctx.db.replace(current._id, value);
  else await ctx.db.insert(table, value);
}

/** Hard-delete matching typed + blob rows for one entity. */
export async function deleteBoth(
  ctx: { db: any },
  ownerId: string,
  workspaceId: string,
  entityType: EntityTypeName,
  entityId: string,
) {
  const table = typedTableFor(entityType);
  const typed = await findTyped(ctx, table, ownerId, workspaceId, entityId);
  if (typed) await ctx.db.delete(typed._id);
  const blob = await findBlob(ctx, ownerId, workspaceId, entityType, entityId);
  if (blob) await ctx.db.delete(blob._id);
}

/**
 * Upsert a typed row (LWW already decided) and mirror to blob.
 * Returns the written typed document fields.
 */
export async function writeTypedAndMirror(
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
  await mirrorToBlob(ctx, entityType, value as TypedSyncRow);
  return value as TypedSyncRow;
}

/**
 * Upsert a blob row (LWW already decided) and explode to typed.
 */
export async function writeBlobAndMirror(
  ctx: { db: any },
  blob: BlobEntity,
) {
  const ownerId = blob.ownerId;
  if (!ownerId) throw new Error("ownerId required");
  const value = { ...blob };
  delete value._id;
  const current = await findBlob(
    ctx,
    ownerId,
    blob.workspaceId,
    blob.entityType,
    blob.entityId,
  );
  if (current) await ctx.db.replace(current._id, value);
  else await ctx.db.insert("entities", value);
  await mirrorToTyped(ctx, blob.entityType, value);
  return value;
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

export async function getBlobRow(
  ctx: { db: any },
  ownerId: string,
  workspaceId: string,
  entityType: EntityTypeName,
  entityId: string,
) {
  return await findBlob(ctx, ownerId, workspaceId, entityType, entityId);
}

/** Clear up to `take` rows of one entity type from both typed + blob stores.
 * `deleted` counts logical entities (typed preferred); blob mirrors are removed
 * alongside without double-counting.
 */
export async function clearEntityTypeBoth(
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
    const blob = await findBlob(
      ctx,
      ownerId,
      workspaceId,
      entityType,
      row.entityId,
    );
    if (blob) await ctx.db.delete(blob._id);
  }
  let deleted = typedRows.length;
  const remaining = take - deleted;

  // Blob-only orphans (pre-bridge / failed mirror).
  if (remaining > 0) {
    const blobRows = await ctx.db
      .query("entities")
      .withIndex("by_owner_and_workspace_and_entity", (q: any) =>
        q
          .eq("ownerId", ownerId)
          .eq("workspaceId", workspaceId)
          .eq("entityType", entityType),
      )
      .take(remaining);
    for (const row of blobRows) {
      await ctx.db.delete(row._id);
    }
    deleted += blobRows.length;
  }

  const moreTyped = await ctx.db
    .query(table)
    .withIndex("by_owner_workspace_entity", (q: any) =>
      q.eq("ownerId", ownerId).eq("workspaceId", workspaceId),
    )
    .first();
  const moreBlob = await ctx.db
    .query("entities")
    .withIndex("by_owner_and_workspace_and_entity", (q: any) =>
      q
        .eq("ownerId", ownerId)
        .eq("workspaceId", workspaceId)
        .eq("entityType", entityType),
    )
    .first();
  return { deleted, exhausted: !moreTyped && !moreBlob };
}
