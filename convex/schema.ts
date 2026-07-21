import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import { entityTypeValidator, payloadValidator, versionValidator } from "./values";

export default defineSchema({
  entities: defineTable({
    // Optional only so pre-auth rows can remain orphaned during rollout. All
    // authenticated reads and writes require and index by this value.
    ownerId: v.optional(v.string()),
    workspaceId: v.string(),
    entityType: entityTypeValidator,
    entityId: v.string(),
    version: versionValidator,
    payload: payloadValidator,
    deleted: v.boolean(),
    revision: v.number(),
  })
    .index("by_entity_type", ["entityType"])
    .index("by_deleted", ["deleted"])
    .index("by_owner_and_workspace_and_entity", [
      "ownerId",
      "workspaceId",
      "entityType",
      "entityId",
    ])
    .index("by_owner_and_workspace_and_revision", [
      "ownerId",
      "workspaceId",
      "revision",
    ]),
  workspaces: defineTable({
    ownerId: v.optional(v.string()),
    workspaceId: v.string(),
    revision: v.number(),
    /** Display name for the account owner. Optional so existing rows keep validating. */
    name: v.optional(v.string()),
    /** Email for the account owner. Optional so existing rows keep validating. */
    email: v.optional(v.string()),
  }).index("by_owner_and_workspace", ["ownerId", "workspaceId"]),
  // Daily ECB reference rates (via Frankfurter), one row per calendar date.
  // `rates` maps a currency code to units of that currency per 1 unit of `base`.
  // Populated once per day by `refreshRates`; clients and recurring materialization
  // read via `exchangeRates:latest` / `rateOn` — never call Frankfurter themselves.
  exchangeRates: defineTable({
    date: v.string(),
    base: v.string(),
    rates: v.record(v.string(), v.number()),
    fetchedAt: v.number(),
  }).index("by_date", ["date"]),
});
