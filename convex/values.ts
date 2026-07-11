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
  defaultView: v.union(
    v.literal("home"),
    v.literal("tx"),
    v.literal("stats"),
    v.literal("recurring"),
    v.literal("budgets"),
    v.literal("account"),
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
