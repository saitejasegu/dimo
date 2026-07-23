import { internalMutationGeneric } from "convex/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";
import { TYPED_TABLE_BY_ENTITY, type EntityTypeName } from "./values";

/* eslint-disable @typescript-eslint/no-explicit-any */

const PAGE_SIZE = 50;
const MS_PER_DAY = 24 * 60 * 60 * 1000;

/** Default when TOMBSTONE_RETENTION_DAYS is unset or invalid. Keep client constants aligned. */
export const DEFAULT_TOMBSTONE_RETENTION_DAYS = 90;

/**
 * Server-only retention window for deleted entity rows.
 * Reads Convex deploy env TOMBSTONE_RETENTION_DAYS; never exposed to clients.
 */
export function retentionDays(
  envValue: string | undefined = process.env.TOMBSTONE_RETENTION_DAYS,
): number {
  if (envValue == null || envValue.trim() === "") {
    return DEFAULT_TOMBSTONE_RETENTION_DAYS;
  }
  const parsed = Number.parseInt(envValue, 10);
  if (!Number.isFinite(parsed) || parsed < 1) {
    return DEFAULT_TOMBSTONE_RETENTION_DAYS;
  }
  return parsed;
}

const TYPED_TABLES = Object.values(TYPED_TABLE_BY_ENTITY);

/**
 * Hard-deletes tombstones older than the configured retention window.
 * One `.paginate()` per invocation (Convex limit); continues across typed
 * tables via scheduled follow-ups.
 * Does not bump workspace revisions.
 */
export const purgeExpired = internalMutationGeneric({
  args: {
    cursor: v.optional(v.union(v.string(), v.null())),
    tableIndex: v.optional(v.number()),
    /** Optional clock for tests so retention cutoffs stay deterministic. */
    now: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const now = args.now ?? Date.now();
    const days = retentionDays();
    const cutoff = now - days * MS_PER_DAY;
    const tableIndex = args.tableIndex ?? 0;

    if (tableIndex >= TYPED_TABLES.length) {
      return { purged: 0, hasMore: false, cutoff, days, tableIndex };
    }

    const table = TYPED_TABLES[tableIndex];
    const page = await ctx.db
      .query(table)
      .withIndex("by_deleted", (q: any) => q.eq("deleted", true))
      .paginate({ cursor: args.cursor ?? null, numItems: PAGE_SIZE });

    let purged = 0;
    for (const row of page.page) {
      if (row.version.timestamp < cutoff) {
        await ctx.db.delete(row._id);
        purged += 1;
      }
    }

    let hasMore = false;
    let nextCursor: string | null = null;
    let nextTableIndex = tableIndex;

    if (!page.isDone) {
      hasMore = true;
      nextCursor = page.continueCursor;
      nextTableIndex = tableIndex;
    } else if (tableIndex + 1 < TYPED_TABLES.length) {
      hasMore = true;
      nextCursor = null;
      nextTableIndex = tableIndex + 1;
    }

    if (hasMore) {
      await ctx.scheduler.runAfter(0, internal.tombstonePurge.purgeExpired, {
        cursor: nextCursor,
        tableIndex: nextTableIndex,
        now,
      });
    }

    return {
      purged,
      hasMore,
      cutoff,
      days,
      tableIndex,
      nextCursor,
      nextTableIndex,
    };
  },
});

/** Helper for tests / clarity — entity type → typed table. */
export function typedTableFor(entityType: EntityTypeName) {
  return TYPED_TABLE_BY_ENTITY[entityType];
}
