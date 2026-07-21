import type {
  Currency,
  NotificationSettings,
  PaymentMethodType,
  ThemePreference,
  StatsRange,
  ViewKey,
  WeekStart,
} from "@/lib/types";

export const WORKSPACE_ID = "global" as const;

/**
 * Private local tombstone retention (days). Keep aligned with Convex
 * TOMBSTONE_RETENTION_DAYS default — not user-visible or synced.
 */
export const TOMBSTONE_RETENTION_DAYS = 90;

export type EntityType =
  | "category"
  | "paymentMethod"
  | "transaction"
  | "recurring"
  | "lend"
  | "emailMessage"
  | "preferences";

/** Native-owned types the web client must not hard-replace on Sync now. */
export type WebOwnedEntityType = Exclude<EntityType, "lend" | "emailMessage">;

/** Entity types this web app owns and replaces on Sync now. Lending and email
 * suggestions are native-owned and read-only on web. */
export const OWNED_ENTITY_TYPES: readonly WebOwnedEntityType[] = [
  "category",
  "paymentMethod",
  "transaction",
  "recurring",
  "preferences",
] as const;

/**
 * Every entity type the sync server accepts. Used for account wipe so cloud
 * rows from other clients (e.g. iOS lending / email) are not left behind.
 */
export const ALL_CLOUD_ENTITY_TYPES = [
  "category",
  "paymentMethod",
  "transaction",
  "recurring",
  "lend",
  "emailMessage",
  "preferences",
] as const;

export type CloudEntityType = (typeof ALL_CLOUD_ENTITY_TYPES)[number];

export interface LogicalVersion {
  timestamp: number;
  counter: number;
  deviceId: string;
}

/** Fallback when a category has no emoji yet (pre-emoji data). */
export const DEFAULT_CATEGORY_EMOJI = "🙂";

export interface CategoryEntity {
  id: string;
  name: string;
  /** Single emoji used as the category icon. */
  emoji: string;
  monthlyBudgetMinor: number | null;
  tint: "green" | "neutral";
  sortOrder: number;
  system: boolean;
}

export interface PaymentMethodEntity {
  id: string;
  name: string;
  type: PaymentMethodType;
  detail: string;
  archived: boolean;
}

export interface TransactionEntity {
  id: string;
  name: string;
  amountMinor: number;
  occurredAt: number;
  categoryId: string;
  paymentMethodId: string | null;
  /**
   * Denomination of `amountMinor` — the account default at write time.
   * New writers always set it so a later preferences change cannot reinterpret
   * historical amounts. Absent only on legacy rows.
   */
  currency?: string;
  /** Original currency when entered in a non-default currency. Absent = `currency`. */
  sourceCurrency?: string;
  /** Original amount in `sourceCurrency` minor units (kept for display/edit). */
  sourceAmountMinor?: number;
  /** Rate used to convert `sourceCurrency` → `currency` (major-unit ratio). */
  exchangeRate?: number;
}

export interface RecurringEntity {
  id: string;
  name: string;
  amountMinor: number;
  categoryId: string;
  paymentMethodId: string | null;
  frequency: "monthly" | "yearly";
  anchorDate: string;
  paused: boolean;
  /** Currency the amount is denominated in. Absent only on legacy rows. */
  currency?: string;
}

export interface LendEntity {
  id: string;
  contactName: string;
  /** Optional on legacy rows; the contact name is used as a stable fallback. */
  contactId?: string;
  amountMinor: number;
  occurredAt: number;
  comment: string;
  /** Missing on legacy rows and treated as money lent. */
  kind?: "lent" | "repaid";
}

/** Native-owned reviewed Gmail suggestion, including full normalized body. */
export interface EmailMessageEntity {
  id: string;
  accountId: string;
  accountEmail: string;
  gmailMessageId: string;
  threadId: string;
  rfcMessageId?: string | null;
  senderName?: string | null;
  senderAddress: string;
  subject: string;
  snippet: string;
  internalDate: number;
  /** Full normalized plain-text body. Optional for legacy cloud rows. */
  normalizedBodyText?: string | null;
  analyzerType?: string | null;
  modelVersion?: string | null;
  promptVersion?: number | null;
  classification?: string | null;
  merchant?: string | null;
  amount?: string | null;
  currency?: string | null;
  occurredAt?: number | null;
  categoryId?: string | null;
  paymentMethodId?: string | null;
  paymentLastFour?: string | null;
  reference?: string | null;
  state: "added" | "dismissed" | "refundApplied" | "pendingPurchase" | "pendingRefund";
  linkedTransactionId?: string | null;
  analyzedAt?: number | null;
  reviewedAt?: number | null;
  createdAt: number;
  updatedAt: number;
}

export interface PreferencesEntity {
  id: "preferences";
  profileName: string;
  profileEmail: string;
  currency: Currency;
  weekStart: WeekStart;
  theme: ThemePreference;
  /** Mobile nav glass fill, 40–100. */
  navGlassOpacity: number;
  defaultView: ViewKey;
  defaultStatsRange: StatsRange;
  notifications: NotificationSettings;
  defaultPaymentMethodId: string;
}

export interface EntityPayloadMap {
  category: CategoryEntity;
  paymentMethod: PaymentMethodEntity;
  transaction: TransactionEntity;
  recurring: RecurringEntity;
  lend: LendEntity;
  emailMessage: EmailMessageEntity;
  preferences: PreferencesEntity;
}

export type EntityPayload = EntityPayloadMap[EntityType];

export interface StoredEntity<T extends EntityType = EntityType> {
  key: string;
  workspaceId: typeof WORKSPACE_ID;
  entityType: T;
  entityId: string;
  version: LogicalVersion;
  payload: EntityPayloadMap[T];
  deleted: boolean;
  serverRevision: number;
}

export interface SyncOperation<T extends EntityType = EntityType> {
  operationId: string;
  key: string;
  workspaceId: typeof WORKSPACE_ID;
  entityType: T;
  entityId: string;
  version: LogicalVersion;
  payload: EntityPayloadMap[T];
  deleted: boolean;
  status: "pending" | "blocked";
  attempts: number;
  lastError: string | null;
  createdAt: number;
}

export const entityKey = (type: EntityType, id: string) =>
  `${WORKSPACE_ID}:${type}:${id}`;

export function compareVersions(a: LogicalVersion, b: LogicalVersion): number {
  if (a.timestamp !== b.timestamp) return a.timestamp - b.timestamp;
  if (a.counter !== b.counter) return a.counter - b.counter;
  return a.deviceId.localeCompare(b.deviceId);
}

export const CASH_PAYMENT_METHOD: PaymentMethodEntity = {
  id: "payment-method-cash",
  name: "Cash",
  type: "Cash",
  detail: "",
  archived: false,
};

export const DEFAULT_PREFERENCES: PreferencesEntity = {
  id: "preferences",
  profileName: "",
  profileEmail: "",
  currency: "INR",
  weekStart: "Mon",
  theme: "light",
  navGlassOpacity: 40,
  defaultView: "home",
  defaultStatsRange: "1Y",
  notifications: { bills: true, budget: true, weekly: false, large: true },
  defaultPaymentMethodId: CASH_PAYMENT_METHOD.id,
};
