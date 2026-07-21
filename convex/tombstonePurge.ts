import { internalMutationGeneric } from "convex/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";

/* Generic Convex functions intentionally use untyped index builders until a
   deployment is linked and Convex generates its schema-specific bindings. */
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

/**
 * Hard-deletes tombstones older than the configured retention window.
 * Pages across all owners via by_deleted; does not bump workspace revisions.
 */
export const purgeExpired = internalMutationGeneric({
  args: {
    cursor: v.optional(v.union(v.string(), v.null())),
    /** Optional clock for tests so retention cutoffs stay deterministic. */
    now: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const now = args.now ?? Date.now();
    const days = retentionDays();
    const cutoff = now - days * MS_PER_DAY;

    const page = await ctx.db
      .query("entities")
      .withIndex("by_deleted", (q: any) => q.eq("deleted", true))
      .paginate({ cursor: args.cursor ?? null, numItems: PAGE_SIZE });

    let purged = 0;
    for (const row of page.page) {
      if (row.version.timestamp < cutoff) {
        await ctx.db.delete(row._id);
        purged += 1;
      }
    }

    if (!page.isDone) {
      await ctx.scheduler.runAfter(0, internal.tombstonePurge.purgeExpired, {
        cursor: page.continueCursor,
        now,
      });
    }

    return { purged, hasMore: !page.isDone, cutoff, days };
  },
});
