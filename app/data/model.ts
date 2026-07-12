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

export type EntityType =
  | "category"
  | "paymentMethod"
  | "transaction"
  | "recurring"
  | "preferences";

/** Entity types this web app owns and replaces on Sync now. */
export const OWNED_ENTITY_TYPES: readonly EntityType[] = [
  "category",
  "paymentMethod",
  "transaction",
  "recurring",
  "preferences",
] as const;

/**
 * Every entity type the sync server accepts. Used for account wipe so cloud
 * rows from other clients (e.g. iOS lending) are not left behind.
 */
export const ALL_CLOUD_ENTITY_TYPES = [
  "category",
  "paymentMethod",
  "transaction",
  "recurring",
  "lend",
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

export const DEFAULT_CATEGORY_ENTITIES: CategoryEntity[] = [
  ["category-dining", "Dining", "🍽️", "green"],
  ["category-groceries", "Groceries", "🛒", "neutral"],
  ["category-bills", "Bills", "📄", "green"],
  ["category-transit", "Transit", "🚌", "neutral"],
  ["category-shopping", "Shopping", "🛍️", "neutral"],
].map(([id, name, emoji, tint], sortOrder) => ({
  id,
  name,
  emoji,
  tint: tint as CategoryEntity["tint"],
  sortOrder,
  system: true,
  monthlyBudgetMinor: null,
}));

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
