import { v } from "convex/values";

export const entityTypeValidator = v.union(
  v.literal("category"),
  v.literal("paymentMethod"),
  v.literal("transaction"),
  v.literal("recurring"),
  v.literal("preferences"),
);

export const versionValidator = v.object({
  timestamp: v.number(),
  counter: v.number(),
  deviceId: v.string(),
});

export const notificationValidator = v.object({
  bills: v.boolean(),
  budget: v.boolean(),
  weekly: v.boolean(),
  large: v.boolean(),
});

export const categoryValidator = v.object({
  id: v.string(),
  name: v.string(),
  /** Optional for backwards compatibility with pre-emoji category payloads. */
  emoji: v.optional(v.string()),
  monthlyBudgetMinor: v.union(v.number(), v.null()),
  tint: v.union(v.literal("green"), v.literal("neutral")),
  sortOrder: v.number(),
  system: v.boolean(),
});

export const paymentMethodValidator = v.object({
  id: v.string(),
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
});

export const transactionValidator = v.object({
  id: v.string(),
  name: v.string(),
  amountMinor: v.number(),
  occurredAt: v.number(),
  categoryId: v.string(),
  paymentMethodId: v.union(v.string(), v.null()),
});

export const recurringValidator = v.object({
  id: v.string(),
  name: v.string(),
  amountMinor: v.number(),
  categoryId: v.string(),
  paymentMethodId: v.union(v.string(), v.null()),
  frequency: v.union(v.literal("monthly"), v.literal("yearly")),
  anchorDate: v.string(),
  paused: v.boolean(),
});

export const preferencesValidator = v.object({
  id: v.literal("preferences"),
  profileName: v.string(),
  profileEmail: v.string(),
  currency: v.union(v.literal("INR"), v.literal("USD"), v.literal("EUR")),
  weekStart: v.union(v.literal("Mon"), v.literal("Sun")),
  // Optional so preferences written by older clients continue to sync. The
  // app normalizes a missing value to the system theme.
  theme: v.optional(
    v.union(v.literal("system"), v.literal("light"), v.literal("dark")),
  ),
  defaultView: v.union(
    v.literal("home"),
    v.literal("tx"),
    v.literal("stats"),
    v.literal("recurring"),
    v.literal("budgets"),
    v.literal("account"),
  ),
  // Optional so preferences written by older clients continue to sync.
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
  notifications: notificationValidator,
  defaultPaymentMethodId: v.string(),
});

export const payloadValidator = v.union(
  categoryValidator,
  paymentMethodValidator,
  transactionValidator,
  recurringValidator,
  preferencesValidator,
);

export const operationValidator = v.object({
  operationId: v.string(),
  workspaceId: v.string(),
  entityType: entityTypeValidator,
  entityId: v.string(),
  version: versionValidator,
  payload: payloadValidator,
  deleted: v.boolean(),
});
