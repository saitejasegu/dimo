import { v } from "convex/values";

export const entityTypeValidator = v.union(
  v.literal("category"),
  v.literal("paymentMethod"),
  v.literal("transaction"),
  v.literal("recurring"),
  v.literal("lend"),
  v.literal("emailMessage"),
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
  // Denomination of `amountMinor` — the account default currency at write time.
  // New writers always include it so a later preferences.currency change cannot
  // reinterpret historical amounts. Absence is accepted only for legacy rows and
  // means "use the current account default". Uses v.string() with an app-side
  // allow-list so the enterable set can grow without a schema migration.
  currency: v.optional(v.string()),
  // Foreign-currency origin. Absent means the amount was entered in `currency`
  // (or the account default for legacy rows). `amountMinor` is the value in
  // `currency`; these preserve the original entry for display/edit.
  sourceCurrency: v.optional(v.string()),
  sourceAmountMinor: v.optional(v.number()),
  exchangeRate: v.optional(v.number()),
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
  // Currency the recurring amount (`amountMinor`) is denominated in. New writers
  // always include it; absence is accepted only for legacy rows and means the
  // account default currency. Each materialized occurrence is
  // converted from this currency at that day's rate. Uses v.string() with an
  // app-side allow-list so the enterable set can grow without a migration.
  currency: v.optional(v.string()),
});

export const lendValidator = v.object({
  id: v.string(),
  contactName: v.string(),
  /** Opaque device address-book identifier of the picked contact, used to
   * tell apart contacts sharing a name. Never contains photo data.
   * Optional so rows written before contact linking existed keep syncing. */
  contactId: v.optional(v.string()),
  amountMinor: v.number(),
  occurredAt: v.number(),
  comment: v.string(),
  /** Direction of money. Optional so rows written before repayments existed
   * keep syncing; a missing value means "lent". */
  kind: v.optional(v.union(v.literal("lent"), v.literal("repaid"))),
});

/** Native-owned reviewed Gmail suggestion. Includes the full normalized body
 * text. OAuth credentials are never included. `normalizedBodyText` is optional
 * so rows written before body sync still validate. */
export const emailMessageValidator = v.object({
  id: v.string(),
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
  // Optional so preferences written by older clients continue to sync.
  navGlassOpacity: v.optional(v.number()),
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
  lendValidator,
  emailMessageValidator,
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
