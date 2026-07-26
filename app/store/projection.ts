import {
  DEFAULT_CATEGORY_EMOJI,
  DEFAULT_PREFERENCES,
  payloadFromStored,
  type CategoryEntity,
  type EntityType,
  type LendEntity,
  type PaymentMethodEntity,
  type PreferencesEntity,
  type RecurringEntity,
  type StoredRow,
  type TransactionEntity,
} from "@/data/model";
import {
  formatTransactionDay,
  formatTransactionTime,
  nextOccurrence,
  recurringDueLabel,
} from "@/lib/dates";
import {
  paymentMethodLabel,
  resolvePaymentMethodId,
  type CategoryLimits,
  type EnterableCurrency,
  type Lend,
  type PaymentMethod,
  type PaymentMethodOption,
  type Recurring,
  type Transaction,
} from "@/lib/types";
import {
  toMajorUnits,
  transactionAmountInDefault,
  type RateTable,
} from "@/features/currency/rates";

/** Per-type content hashes so unchanged entity types can skip remapping. */
export interface EntityFingerprints {
  category: number;
  paymentMethod: number;
  transaction: number;
  recurring: number;
  lend: number;
  preferences: number;
}

const EMPTY_FINGERPRINTS: EntityFingerprints = {
  category: 0,
  paymentMethod: 0,
  transaction: 0,
  recurring: 0,
  lend: 0,
  preferences: 0,
};

/** Projected UI models plus the inputs they were derived from. */
export interface ProjectionSnapshot {
  fingerprints: EntityFingerprints;
  ratesDate: string | null;
  categories: CategoryEntity[];
  limits: CategoryLimits;
  paymentMethods: PaymentMethodOption[];
  transactions: Transaction[];
  recurring: Recurring[];
  lends: Lend[];
  preferences: PreferencesEntity;
  lastPaymentMethod: PaymentMethod | null;
}

export type StoredRowEntry = { entityType: EntityType; row: StoredRow };

/** FNV-1a over the identity fields that decide whether a projection is stale. */
function hashString(hash: number, value: string): number {
  let next = hash;
  for (let index = 0; index < value.length; index += 1) {
    next ^= value.charCodeAt(index);
    next = Math.imul(next, 16_777_619);
  }
  return next;
}

function hashNumber(hash: number, value: number): number {
  return Math.imul(hash ^ value, 16_777_619);
}

/**
 * One pass over the rows, hashing each type separately. Categories and preferences
 * hash their whole payload because their *content* (emoji, budget, currency) feeds
 * other types' projections; the rest are identified by id + logical version, which
 * already changes on every edit.
 */
export function computeFingerprints(rows: StoredRowEntry[]): EntityFingerprints {
  const hashes: Record<keyof EntityFingerprints, number> = { ...EMPTY_FINGERPRINTS };
  const counts: Record<keyof EntityFingerprints, number> = { ...EMPTY_FINGERPRINTS };
  for (const { entityType, row } of rows) {
    if (entityType === "emailMessage") continue;
    const key = entityType as keyof EntityFingerprints;
    let hash = hashes[key] || 2_166_136_261;
    hash = hashString(hash, row.entityId);
    hash = hashNumber(hash, row.version.timestamp);
    hash = hashNumber(hash, row.version.counter);
    hash = hashNumber(hash, row.deleted ? 1 : 0);
    if (key === "category" || key === "preferences") {
      hash = hashString(hash, JSON.stringify(row));
    }
    hashes[key] = hash;
    counts[key] += 1;
  }
  for (const key of Object.keys(hashes) as Array<keyof EntityFingerprints>) {
    hashes[key] = hashNumber(hashes[key], counts[key]);
  }
  return hashes;
}

function sameFingerprints(a: EntityFingerprints, b: EntityFingerprints): boolean {
  return (
    a.category === b.category &&
    a.paymentMethod === b.paymentMethod &&
    a.transaction === b.transaction &&
    a.recurring === b.recurring &&
    a.lend === b.lend &&
    a.preferences === b.preferences
  );
}

/**
 * Build UI models from stored rows, reusing whatever the previous snapshot already
 * projected. Returns `null` when nothing observable changed, so the caller can skip
 * dispatching entirely.
 */
export function projectEntities(
  rows: StoredRowEntry[],
  options: {
    rates: RateTable | null;
    lastPaymentMethodId: string | null | undefined;
    previous: ProjectionSnapshot | null;
  },
): ProjectionSnapshot | null {
  const { rates, lastPaymentMethodId, previous } = options;
  const fingerprints = computeFingerprints(rows);
  const ratesDate = rates?.date ?? null;

  if (
    previous &&
    sameFingerprints(previous.fingerprints, fingerprints) &&
    previous.ratesDate === ratesDate &&
    previous.lastPaymentMethod ===
      lastPaymentMethodLabel(lastPaymentMethodId, previous.paymentMethods)
  ) {
    return null;
  }

  const previousPrints = previous?.fingerprints;
  const rebuildCategories =
    !previousPrints || previousPrints.category !== fingerprints.category;
  const rebuildPreferences =
    !previousPrints || previousPrints.preferences !== fingerprints.preferences;
  const rebuildPaymentMethods =
    !previousPrints ||
    previousPrints.paymentMethod !== fingerprints.paymentMethod ||
    rebuildPreferences;
  const rebuildTransactions =
    !previousPrints ||
    previousPrints.transaction !== fingerprints.transaction ||
    rebuildCategories ||
    rebuildPaymentMethods ||
    previous?.ratesDate !== ratesDate;
  const rebuildRecurring =
    !previousPrints ||
    previousPrints.recurring !== fingerprints.recurring ||
    rebuildCategories ||
    rebuildPreferences;
  const rebuildLends = !previousPrints || previousPrints.lend !== fingerprints.lend;

  const active = rows.filter(({ row }) => !row.deleted);
  const collect = <T,>(entityType: EntityType): T[] =>
    active
      .filter((entry) => entry.entityType === entityType)
      .map((entry) => payloadFromStored(entityType, entry.row as never) as T);

  const categories = rebuildCategories
    ? collect<CategoryEntity & { emoji?: string }>("category")
        .map((payload) => ({
          ...payload,
          emoji: payload.emoji || DEFAULT_CATEGORY_EMOJI,
        }))
        .sort((a, b) => a.sortOrder - b.sortOrder)
    : (previous?.categories ?? []);

  const limits: CategoryLimits = rebuildCategories
    ? Object.fromEntries(
        categories.map((category) => [
          category.name,
          category.monthlyBudgetMinor === null
            ? null
            : category.monthlyBudgetMinor / 100,
        ]),
      )
    : (previous?.limits ?? {});

  const preferences: PreferencesEntity = rebuildPreferences
    ? {
        ...DEFAULT_PREFERENCES,
        ...(collect<Partial<PreferencesEntity>>("preferences")[0] ?? {}),
      }
    : (previous?.preferences ?? DEFAULT_PREFERENCES);

  const paymentMethods: PaymentMethodOption[] = rebuildPaymentMethods
    ? collect<PaymentMethodEntity>("paymentMethod").map((method) => ({
        ...method,
        isDefault: method.id === preferences.defaultPaymentMethodId,
      }))
    : (previous?.paymentMethods ?? []);

  const categoryMap = new Map(categories.map((c) => [c.id, c]));
  const methodMap = new Map(paymentMethods.map((m) => [m.id, m]));
  const defaultMethodEntity =
    paymentMethods.find((method) => method.isDefault && !method.archived) ??
    paymentMethods.find((method) => !method.archived) ??
    paymentMethods[0];
  const defaultMethodLabel = defaultMethodEntity
    ? paymentMethodLabel(defaultMethodEntity)
    : "Cash";

  const transactions: Transaction[] = rebuildTransactions
    ? collect<TransactionEntity>("transaction")
        .sort((a, b) => b.occurredAt - a.occurredAt)
        .map((t) => {
          const category = categoryMap.get(t.categoryId);
          const method = t.paymentMethodId
            ? methodMap.get(t.paymentMethodId)
            : undefined;
          const currency = (t.currency ?? preferences.currency) as EnterableCurrency;
          const source = t.sourceCurrency
            ? {
                sourceCurrency: t.sourceCurrency as EnterableCurrency,
                sourceAmount: toMajorUnits(t.sourceAmountMinor ?? 0, t.sourceCurrency),
              }
            : {};
          return {
            id: t.id,
            name: t.name,
            amount: transactionAmountInDefault(
              {
                amount: toMajorUnits(t.amountMinor, currency),
                amountMinor: t.amountMinor,
                currency: t.currency,
              },
              preferences.currency,
              rates,
            ),
            amountMinor: t.amountMinor,
            occurredAt: t.occurredAt,
            categoryId: t.categoryId,
            paymentMethodId:
              t.paymentMethodId || resolvePaymentMethodId(null, paymentMethods),
            category: category?.name ?? "Unknown category",
            emoji: category?.emoji ?? DEFAULT_CATEGORY_EMOJI,
            paymentMethod: method ? paymentMethodLabel(method) : defaultMethodLabel,
            time: formatTransactionTime(t.occurredAt),
            day: formatTransactionDay(t.occurredAt),
            green: category?.tint === "green",
            currency,
            ...source,
          };
        })
    : (previous?.transactions ?? []);

  const recurring: Recurring[] = rebuildRecurring
    ? collect<RecurringEntity>("recurring")
        .sort((a, b) => nextOccurrence(a).getTime() - nextOccurrence(b).getTime())
        .map((item) => {
          const category = categoryMap.get(item.categoryId);
          const dueDate = nextOccurrence(item);
          const days = Math.round(
            (dueDate.getTime() - new Date().setHours(0, 0, 0, 0)) / 86_400_000,
          );
          const currency = item.currency as EnterableCurrency | undefined;
          return {
            id: item.id,
            name: item.name,
            amount: toMajorUnits(item.amountMinor, currency ?? preferences.currency),
            amountMinor: item.amountMinor,
            categoryId: item.categoryId,
            paymentMethodId: item.paymentMethodId,
            category: category?.name ?? "Unknown category",
            emoji: category?.emoji ?? DEFAULT_CATEGORY_EMOJI,
            due: recurringDueLabel(item),
            paused: item.paused,
            urgent: days <= 2,
            green: category?.tint === "green",
            anchorDate: item.anchorDate,
            frequency: item.frequency,
            ...(currency ? { currency } : {}),
          };
        })
    : (previous?.recurring ?? []);

  const lends: Lend[] = rebuildLends
    ? collect<LendEntity>("lend")
        .sort((a, b) => b.occurredAt - a.occurredAt)
        .map((item) => ({
          id: item.id,
          contactName: item.contactName,
          contactId: item.contactId?.trim() || item.contactName,
          amount: item.amountMinor / 100,
          amountMinor: item.amountMinor,
          occurredAt: item.occurredAt,
          comment: item.comment,
          kind: item.kind === "repaid" ? ("repaid" as const) : ("lent" as const),
          time: formatTransactionTime(item.occurredAt),
          day: formatTransactionDay(item.occurredAt),
        }))
    : (previous?.lends ?? []);

  return {
    fingerprints,
    ratesDate,
    categories,
    limits,
    paymentMethods,
    transactions,
    recurring,
    lends,
    preferences,
    lastPaymentMethod: lastPaymentMethodLabel(lastPaymentMethodId, paymentMethods),
  };
}

function lastPaymentMethodLabel(
  id: string | null | undefined,
  paymentMethods: PaymentMethodOption[],
): PaymentMethod | null {
  if (!id) return null;
  const method = paymentMethods.find((candidate) => candidate.id === id);
  return method ? paymentMethodLabel(method) : null;
}
