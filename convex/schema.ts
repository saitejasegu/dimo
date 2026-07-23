import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import { versionValidator } from "./values";

const syncMeta = {
  // Optional only so pre-auth rows can remain orphaned during rollout. All
  // authenticated reads and writes require and index by this value.
  ownerId: v.optional(v.string()),
  workspaceId: v.string(),
  entityId: v.string(),
  version: versionValidator,
  deleted: v.boolean(),
  revision: v.number(),
};

export default defineSchema({
  categories: defineTable({
    ...syncMeta,
    name: v.string(),
    emoji: v.optional(v.string()),
    monthlyBudgetMinor: v.union(v.number(), v.null()),
    tint: v.union(v.literal("green"), v.literal("neutral")),
    sortOrder: v.number(),
    system: v.boolean(),
  })
    .index("by_owner_workspace_entity", ["ownerId", "workspaceId", "entityId"])
    .index("by_owner_workspace_revision", ["ownerId", "workspaceId", "revision"])
    .index("by_deleted", ["deleted"]),

  paymentMethods: defineTable({
    ...syncMeta,
    name: v.string(),
    type: v.union(
      v.literal("UPI"),
      v.literal("Card"),
      v.literal("Wallet"),
      v.literal("Cash"),
      v.literal("Bank"),
    ),
    detail: v.string(),
    archived: v.boolean(),
  })
    .index("by_owner_workspace_entity", ["ownerId", "workspaceId", "entityId"])
    .index("by_owner_workspace_revision", ["ownerId", "workspaceId", "revision"])
    .index("by_deleted", ["deleted"]),

  transactions: defineTable({
    ...syncMeta,
    name: v.string(),
    amountMinor: v.number(),
    occurredAt: v.number(),
    categoryId: v.string(),
    paymentMethodId: v.union(v.string(), v.null()),
    currency: v.optional(v.string()),
    sourceCurrency: v.optional(v.string()),
    sourceAmountMinor: v.optional(v.number()),
    exchangeRate: v.optional(v.number()),
  })
    .index("by_owner_workspace_entity", ["ownerId", "workspaceId", "entityId"])
    .index("by_owner_workspace_revision", ["ownerId", "workspaceId", "revision"])
    .index("by_owner_workspace_occurredAt", [
      "ownerId",
      "workspaceId",
      "occurredAt",
    ])
    .index("by_owner_workspace_category", [
      "ownerId",
      "workspaceId",
      "categoryId",
    ])
    .index("by_deleted", ["deleted"]),

  recurring: defineTable({
    ...syncMeta,
    name: v.string(),
    amountMinor: v.number(),
    categoryId: v.string(),
    paymentMethodId: v.union(v.string(), v.null()),
    frequency: v.union(v.literal("monthly"), v.literal("yearly")),
    anchorDate: v.string(),
    paused: v.boolean(),
    currency: v.optional(v.string()),
  })
    .index("by_owner_workspace_entity", ["ownerId", "workspaceId", "entityId"])
    .index("by_owner_workspace_revision", ["ownerId", "workspaceId", "revision"])
    .index("by_owner_workspace_anchorDate", [
      "ownerId",
      "workspaceId",
      "anchorDate",
    ])
    .index("by_deleted", ["deleted"]),

  lends: defineTable({
    ...syncMeta,
    contactName: v.string(),
    contactId: v.optional(v.string()),
    amountMinor: v.number(),
    occurredAt: v.number(),
    comment: v.string(),
    kind: v.optional(v.union(v.literal("lent"), v.literal("repaid"))),
  })
    .index("by_owner_workspace_entity", ["ownerId", "workspaceId", "entityId"])
    .index("by_owner_workspace_revision", ["ownerId", "workspaceId", "revision"])
    .index("by_owner_workspace_occurredAt", [
      "ownerId",
      "workspaceId",
      "occurredAt",
    ])
    .index("by_deleted", ["deleted"]),

  emailMessages: defineTable({
    ...syncMeta,
    accountId: v.string(),
    accountEmail: v.string(),
    gmailMessageId: v.string(),
    threadId: v.string(),
    rfcMessageId: v.optional(v.union(v.string(), v.null())),
    senderName: v.optional(v.union(v.string(), v.null())),
    senderAddress: v.string(),
    subject: v.string(),
    snippet: v.string(),
    internalDate: v.number(),
    normalizedBodyText: v.optional(v.union(v.string(), v.null())),
    analyzerType: v.optional(v.union(v.string(), v.null())),
    modelVersion: v.optional(v.union(v.string(), v.null())),
    promptVersion: v.optional(v.union(v.number(), v.null())),
    classification: v.optional(v.union(v.string(), v.null())),
    merchant: v.optional(v.union(v.string(), v.null())),
    amount: v.optional(v.union(v.string(), v.null())),
    currency: v.optional(v.union(v.string(), v.null())),
    occurredAt: v.optional(v.union(v.number(), v.null())),
    categoryId: v.optional(v.union(v.string(), v.null())),
    paymentMethodId: v.optional(v.union(v.string(), v.null())),
    paymentLastFour: v.optional(v.union(v.string(), v.null())),
    reference: v.optional(v.union(v.string(), v.null())),
    state: v.union(
      v.literal("added"),
      v.literal("dismissed"),
      v.literal("refundApplied"),
      v.literal("pendingPurchase"),
      v.literal("pendingRefund"),
    ),
    linkedTransactionId: v.optional(v.union(v.string(), v.null())),
    analyzedAt: v.optional(v.union(v.number(), v.null())),
    reviewedAt: v.optional(v.union(v.number(), v.null())),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_owner_workspace_entity", ["ownerId", "workspaceId", "entityId"])
    .index("by_owner_workspace_revision", ["ownerId", "workspaceId", "revision"])
    .index("by_owner_workspace_gmailMessageId", [
      "ownerId",
      "workspaceId",
      "gmailMessageId",
    ])
    .index("by_owner_workspace_state", ["ownerId", "workspaceId", "state"])
    .index("by_deleted", ["deleted"]),

  preferences: defineTable({
    ...syncMeta,
    profileName: v.string(),
    profileEmail: v.string(),
    currency: v.union(v.literal("INR"), v.literal("USD"), v.literal("EUR")),
    weekStart: v.union(v.literal("Mon"), v.literal("Sun")),
    theme: v.optional(
      v.union(v.literal("system"), v.literal("light"), v.literal("dark")),
    ),
    navGlassOpacity: v.optional(v.number()),
    defaultView: v.union(
      v.literal("home"),
      v.literal("tx"),
      v.literal("stats"),
      v.literal("recurring"),
      v.literal("budgets"),
      v.literal("account"),
    ),
    defaultStatsRange: v.optional(
      v.union(
        v.literal("1W"),
        v.literal("M"),
        v.literal("3M"),
        v.literal("6M"),
        v.literal("1Y"),
        v.literal("2Y"),
      ),
    ),
    notifications: v.object({
      bills: v.boolean(),
      budget: v.boolean(),
      weekly: v.boolean(),
      large: v.boolean(),
    }),
    defaultPaymentMethodId: v.string(),
  })
    .index("by_owner_workspace_entity", ["ownerId", "workspaceId", "entityId"])
    .index("by_owner_workspace_revision", ["ownerId", "workspaceId", "revision"])
    .index("by_deleted", ["deleted"]),

  workspaces: defineTable({
    ownerId: v.optional(v.string()),
    workspaceId: v.string(),
    revision: v.number(),
    /** Display name for the account owner. Optional so existing rows keep validating. */
    name: v.optional(v.string()),
    /** Email for the account owner. Optional so existing rows keep validating. */
    email: v.optional(v.string()),
  }).index("by_owner_and_workspace", ["ownerId", "workspaceId"]),

  // Typed per-(date, currency) rates. Base is stored as rate 1.
  exchangeRateEntries: defineTable({
    date: v.string(),
    base: v.string(),
    currency: v.string(),
    rate: v.number(),
    fetchedAt: v.number(),
  })
    .index("by_date_currency", ["date", "currency"])
    .index("by_date", ["date"]),
});
