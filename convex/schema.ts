import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import { entityTypeValidator, payloadValidator, versionValidator } from "./values";

export default defineSchema({
  entities: defineTable({
    workspaceId: v.string(),
    entityType: entityTypeValidator,
    entityId: v.string(),
    version: versionValidator,
    payload: payloadValidator,
    deleted: v.boolean(),
    revision: v.number(),
  })
    .index("by_workspace_entity", ["workspaceId", "entityType", "entityId"])
    .index("by_workspace_revision", ["workspaceId", "revision"]),
  workspaces: defineTable({
    workspaceId: v.string(),
    revision: v.number(),
  }).index("by_workspace", ["workspaceId"]),
});
