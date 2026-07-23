import { Migrations } from "@convex-dev/migrations";
import { components, internal } from "./_generated/api";
import type { DataModel } from "./_generated/dataModel";
import { mirrorToTyped, typedFieldsFromPayload } from "./compat";
import type { EntityTypeName } from "./values";

/* eslint-disable @typescript-eslint/no-explicit-any */

export const migrations = new Migrations<DataModel>(components.migrations);

/**
 * Backfill one blob `entities` row into its typed table. Idempotent: replaces
 * the typed row when present so re-runs converge.
 */
export const backfillEntitiesToTyped = migrations.define({
  table: "entities",
  batchSize: 25,
  migrateOne: async (ctx, row) => {
    if (!row.ownerId) return;
    await mirrorToTyped(ctx, row.entityType as EntityTypeName, {
      ownerId: row.ownerId,
      workspaceId: row.workspaceId,
      entityId: row.entityId,
      version: row.version,
      payload: row.payload as unknown as Record<string, unknown>,
      deleted: row.deleted,
      revision: row.revision,
    });
  },
});

/**
 * Expand one legacy `exchangeRates` blob row into typed `exchangeRateEntries`.
 * Idempotent by (date, currency).
 */
export const backfillExchangeRatesToEntries = migrations.define({
  table: "exchangeRates",
  batchSize: 10,
  migrateOne: async (ctx, row) => {
    const currencies = new Set([...Object.keys(row.rates), row.base]);
    for (const currency of currencies) {
      const rate = currency === row.base ? 1 : row.rates[currency];
      if (!(typeof rate === "number" && rate > 0)) continue;
      const existing = await ctx.db
        .query("exchangeRateEntries")
        .withIndex("by_date_currency", (q: any) =>
          q.eq("date", row.date).eq("currency", currency),
        )
        .unique();
      const fields = {
        date: row.date,
        base: row.base,
        currency,
        rate,
        fetchedAt: row.fetchedAt,
      };
      if (existing) await ctx.db.patch(existing._id, fields);
      else await ctx.db.insert("exchangeRateEntries", fields);
    }
  },
});

/** Run both backfills in order (entities first, then exchange rates). */
export const runBackfill = migrations.runner([
  internal.migrations.backfillEntitiesToTyped,
  internal.migrations.backfillExchangeRatesToEntries,
]);

/** Test helper: explode a payload without writing (parity checks). */
export function explodePayloadForTest(payload: Record<string, unknown>) {
  return typedFieldsFromPayload(payload);
}
