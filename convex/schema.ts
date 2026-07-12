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
});
