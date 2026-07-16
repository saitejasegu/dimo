import { db, type DeviceMetaRecord } from "@/data/db";
import {
  CASH_PAYMENT_METHOD,
  DEFAULT_CATEGORY_EMOJI,
  DEFAULT_PREFERENCES,
  OWNED_ENTITY_TYPES,
  WORKSPACE_ID,
  compareVersions,
  entityKey,
  type CategoryEntity,
  type EmailMessageEntity,
  type EntityPayload,
  type EntityPayloadMap,
  type EntityType,
  type LendEntity,
  type LogicalVersion,
  type PaymentMethodEntity,
  type PreferencesEntity,
  type RecurringEntity,
  type StoredEntity,
  type SyncOperation,
  type TransactionEntity,
} from "@/data/model";

/**
 * Version 4 replays the cloud snapshot once. Some mobile-web databases pulled
 * lending rows before the `kind` field existed and otherwise keep classifying
 * repayments as money lent.
 */
const BOOTSTRAP_VERSION = 4;
const listeners = new Set<() => void>();

export function onLocalWrite(listener: () => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

function notifyWrite() {
  for (const listener of listeners) listener();
}

function randomId() {
  return crypto.randomUUID();
}

async function ensureDevice(): Promise<DeviceMetaRecord> {
  const current = await db.deviceMeta.get("device");
  if (current) return current;
  const created: DeviceMetaRecord = {
    id: "device",
    deviceId: randomId(),
    clockTimestamp: 0,
    clockCounter: 0,
    bootstrapVersion: 0,
    lastPaymentMethodId: null,
  };
  await db.deviceMeta.add(created);
  return created;
}

async function nextVersion(): Promise<LogicalVersion> {
  const device = await ensureDevice();
  const now = Date.now();
  const timestamp = Math.max(now, device.clockTimestamp);
  const counter = timestamp === device.clockTimestamp ? device.clockCounter + 1 : 0;
  await db.deviceMeta.update("device", {
    clockTimestamp: timestamp,
    clockCounter: counter,
  });
  return { timestamp, counter, deviceId: device.deviceId };
}

/** Strip unknown fields and coerce shapes so Convex validators accept local rows. */
export function sanitizePayload<T extends EntityType>(
  entityType: T,
  payload: EntityPayloadMap[T] | EntityPayload,
): EntityPayloadMap[T] {
  switch (entityType) {
    case "category": {
      const value = payload as CategoryEntity & { emoji?: string };
      return {
        id: value.id,
        name: value.name,
        emoji: value.emoji || DEFAULT_CATEGORY_EMOJI,
        monthlyBudgetMinor:
          value.monthlyBudgetMinor == null ? null : Math.round(Number(value.monthlyBudgetMinor)),
        tint: value.tint === "green" ? "green" : "neutral",
        sortOrder: Number(value.sortOrder) || 0,
        system: Boolean(value.system),
      } as EntityPayloadMap[T];
    }
    case "paymentMethod": {
      const value = payload as PaymentMethodEntity;
      const type = value.type;
      const allowed = ["UPI", "Card", "Wallet", "Cash", "Bank"] as const;
      return {
        id: value.id,
        name: value.name,
        type: allowed.includes(type as (typeof allowed)[number]) ? type : "Cash",
        detail: value.detail ?? "",
        archived: Boolean(value.archived),
      } as EntityPayloadMap[T];
    }
    case "transaction": {
      const value = payload as TransactionEntity;
      return {
        id: value.id,
        name: value.name,
        amountMinor: Math.max(1, Math.round(Number(value.amountMinor) || 0)),
        occurredAt: Math.round(Number(value.occurredAt) || Date.now()),
        categoryId: value.categoryId,
        paymentMethodId: value.paymentMethodId ?? null,
      } as EntityPayloadMap[T];
    }
    case "recurring": {
      const value = payload as RecurringEntity;
      const anchor = String(value.anchorDate ?? "");
      return {
        id: value.id,
        name: value.name,
        amountMinor: Math.max(1, Math.round(Number(value.amountMinor) || 0)),
        categoryId: value.categoryId,
        paymentMethodId: value.paymentMethodId ?? null,
        frequency: value.frequency === "yearly" ? "yearly" : "monthly",
        anchorDate: /^\d{4}-\d{2}-\d{2}$/.test(anchor)
          ? anchor
          : new Date().toISOString().slice(0, 10),
        paused: Boolean(value.paused),
      } as EntityPayloadMap[T];
    }
    case "lend": {
      const value = payload as LendEntity;
      const contactName = String(value.contactName ?? "").trim();
      const contactId = String(value.contactId ?? "").trim();
      return {
        id: value.id,
        contactName,
        contactId: contactId || contactName,
        amountMinor: Math.max(1, Math.round(Number(value.amountMinor) || 0)),
        occurredAt: Math.round(Number(value.occurredAt) || Date.now()),
        comment: String(value.comment ?? ""),
        kind: value.kind === "repaid" ? "repaid" : "lent",
      } as EntityPayloadMap[T];
    }
    case "emailMessage": {
      const value = payload as EmailMessageEntity;
      const states = [
        "added",
        "dismissed",
        "refundApplied",
        "pendingPurchase",
        "pendingRefund",
      ] as const;
      const state = states.includes(value.state as (typeof states)[number])
        ? value.state
        : "dismissed";
      const optionalString = (raw: unknown) => {
        if (raw == null) return null;
        const text = String(raw).trim();
        return text ? text : null;
      };
      const optionalNumber = (raw: unknown) => {
        if (raw == null || raw === "") return null;
        const number = Math.round(Number(raw));
        return Number.isFinite(number) ? number : null;
      };
      return {
        id: String(value.id ?? ""),
        accountId: String(value.accountId ?? ""),
        accountEmail: String(value.accountEmail ?? ""),
        gmailMessageId: String(value.gmailMessageId ?? ""),
        threadId: String(value.threadId ?? ""),
        rfcMessageId: optionalString(value.rfcMessageId),
        senderName: optionalString(value.senderName),
        senderAddress: String(value.senderAddress ?? ""),
        subject: String(value.subject ?? ""),
        snippet: String(value.snippet ?? ""),
        internalDate: Math.round(Number(value.internalDate) || 0),
        normalizedBodyText:
          value.normalizedBodyText == null ? null : String(value.normalizedBodyText),
        analyzerType: optionalString(value.analyzerType),
        modelVersion: optionalString(value.modelVersion),
        promptVersion: optionalNumber(value.promptVersion),
        classification: optionalString(value.classification),
        merchant: optionalString(value.merchant),
        amount: optionalString(value.amount),
        currency: optionalString(value.currency),
        occurredAt: optionalNumber(value.occurredAt),
        categoryId: optionalString(value.categoryId),
        paymentMethodId: optionalString(value.paymentMethodId),
        paymentLastFour: optionalString(value.paymentLastFour),
        reference: optionalString(value.reference),
        state,
        linkedTransactionId: optionalString(value.linkedTransactionId),
        analyzedAt: optionalNumber(value.analyzedAt),
        reviewedAt: optionalNumber(value.reviewedAt),
        createdAt: Math.round(Number(value.createdAt) || 0),
        updatedAt: Math.round(Number(value.updatedAt) || 0),
      } as EntityPayloadMap[T];
    }
    case "preferences": {
      const value = payload as PreferencesEntity;
      const currency = value.currency;
      const weekStart = value.weekStart;
      const theme = value.theme;
      const defaultStatsRange = value.defaultStatsRange;
      const statsRanges = ["1W", "M", "3M", "6M", "1Y", "2Y"] as const;
      return {
        id: "preferences",
        profileName: value.profileName ?? "",
        profileEmail: value.profileEmail ?? "",
        currency: currency === "USD" || currency === "EUR" ? currency : "INR",
        weekStart: weekStart === "Sun" ? "Sun" : "Mon",
        theme: theme === "light" || theme === "dark" || theme === "system" ? theme : "light",
        navGlassOpacity: (() => {
          const opacity = Number(value.navGlassOpacity);
          return Number.isFinite(opacity) ? Math.min(100, Math.max(40, Math.round(opacity))) : 40;
        })(),
        defaultView: "home",
        defaultStatsRange: statsRanges.includes(
          defaultStatsRange as (typeof statsRanges)[number],
        )
          ? defaultStatsRange
          : "1Y",
        notifications: {
          bills: Boolean(value.notifications?.bills),
          budget: Boolean(value.notifications?.budget),
          weekly: Boolean(value.notifications?.weekly),
          large: Boolean(value.notifications?.large),
        },
        defaultPaymentMethodId: value.defaultPaymentMethodId || CASH_PAYMENT_METHOD.id,
      } as EntityPayloadMap[T];
    }
    default:
      return payload as EntityPayloadMap[T];
  }
}

async function putLocalOnly<T extends EntityType>(
  entityType: T,
  payload: EntityPayloadMap[T],
  deleted = false,
) {
  const device = await ensureDevice();
  const clean = sanitizePayload(entityType, payload);
  const key = entityKey(entityType, clean.id);
  const entity: StoredEntity<T> = {
    key,
    workspaceId: WORKSPACE_ID,
    entityType,
    entityId: clean.id,
    // Zero version so any cloud row wins on the first pull.
    version: { timestamp: 0, counter: 0, deviceId: device.deviceId },
    payload: clean,
    deleted,
    serverRevision: 0,
  };
  await db.entities.put(entity as StoredEntity);
}

async function putInCurrentTransaction<T extends EntityType>(
  entityType: T,
  payload: EntityPayloadMap[T],
  deleted = false,
) {
  const version = await nextVersion();
  const clean = sanitizePayload(entityType, payload);
  const key = entityKey(entityType, clean.id);
  const entity: StoredEntity<T> = {
    key,
    workspaceId: WORKSPACE_ID,
    entityType,
    entityId: clean.id,
    version,
    payload: clean,
    deleted,
    serverRevision: 0,
  };
  const operation: SyncOperation<T> = {
    operationId: randomId(), key, workspaceId: WORKSPACE_ID,
    entityType, entityId: clean.id, version, payload: clean, deleted,
    status: "pending",
    attempts: 0,
    lastError: null,
    createdAt: Date.now(),
  };
  await db.entities.put(entity as StoredEntity);
  await db.outbox.put(operation as SyncOperation);
}

export async function initializeLocalDatabase() {
  await db.open();
  await db.transaction("rw", db.deviceMeta, db.entities, db.outbox, db.syncMeta, async () => {
    const device = await ensureDevice();
    const shouldReplayCloudSnapshot = device.bootstrapVersion < 4;
    if (device.bootstrapVersion < BOOTSTRAP_VERSION) {
      // Cash + preferences only — new accounts start with no seeded categories.
      if (!(await db.entities.get(entityKey("paymentMethod", CASH_PAYMENT_METHOD.id)))) {
        await putLocalOnly("paymentMethod", CASH_PAYMENT_METHOD);
      }
      if (!(await db.entities.get(entityKey("preferences", DEFAULT_PREFERENCES.id)))) {
        await putLocalOnly("preferences", DEFAULT_PREFERENCES);
      }
      await db.deviceMeta.update("device", { bootstrapVersion: BOOTSTRAP_VERSION });
    }
    if (!(await db.syncMeta.get(WORKSPACE_ID))) {
      await db.syncMeta.add({
        workspaceId: WORKSPACE_ID,
        lastPulledRevision: 0,
        lastSyncedAt: null,
        error: null,
        syncing: false,
      });
    } else if (shouldReplayCloudSnapshot) {
      await db.syncMeta.update(WORKSPACE_ID, { lastPulledRevision: 0 });
    }
  });
  if (typeof navigator !== "undefined") {
    void navigator.storage?.persist?.().catch(() => false);
  }
  notifyWrite();
}

/**
 * After pull, queue cash / preferences that never landed from the server so a
 * brand-new workspace still receives those defaults (not categories).
 */
export async function enqueueUnsyncedDefaults() {
  const defaults: Array<{ entityType: EntityType; payload: EntityPayload }> = [
    { entityType: "paymentMethod", payload: CASH_PAYMENT_METHOD },
    { entityType: "preferences", payload: DEFAULT_PREFERENCES },
  ];
  let enqueued = false;
  await db.transaction("rw", db.deviceMeta, db.entities, db.outbox, async () => {
    for (const { entityType, payload } of defaults) {
      const key = entityKey(entityType, payload.id);
      const existing = await db.entities.get(key);
      if (!existing || existing.deleted || existing.serverRevision > 0) continue;
      if (await db.outbox.get(key)) continue;
      await putInCurrentTransaction(
        entityType,
        existing.payload as EntityPayloadMap[typeof entityType],
      );
      enqueued = true;
    }
  });
  if (enqueued) notifyWrite();
}

export async function saveEntity<T extends EntityType>(
  entityType: T,
  payload: EntityPayloadMap[T],
) {
  await db.transaction("rw", db.deviceMeta, db.entities, db.outbox, async () => {
    await putInCurrentTransaction(entityType, payload);
  });
  notifyWrite();
}

/** Persist a related set of entities atomically, with one sync operation per row. */
export async function saveEntities(
  entities: Array<{ entityType: EntityType; payload: EntityPayload }>,
) {
  await db.transaction("rw", db.deviceMeta, db.entities, db.outbox, async () => {
    for (const entity of entities) {
      await putInCurrentTransaction(entity.entityType, entity.payload);
    }
  });
  notifyWrite();
}

export async function removeEntity<T extends EntityType>(
  entityType: T,
  id: string,
) {
  const current = await db.entities.get(entityKey(entityType, id));
  if (!current || current.deleted) return;
  await db.transaction("rw", db.deviceMeta, db.entities, db.outbox, async () => {
    await putInCurrentTransaction(entityType, current.payload as EntityPayloadMap[T], true);
  });
  notifyWrite();
}

export async function setLastPaymentMethod(id: string | null) {
  await ensureDevice();
  await db.deviceMeta.update("device", { lastPaymentMethodId: id });
}

export async function observeRemoteVersion(version: LogicalVersion) {
  await ensureDevice();
  const device = await db.deviceMeta.get("device");
  if (!device) return;
  if (version.timestamp > device.clockTimestamp) {
    await db.deviceMeta.update("device", {
      clockTimestamp: version.timestamp,
      clockCounter: version.counter,
    });
  } else if (
    version.timestamp === device.clockTimestamp &&
    version.counter > device.clockCounter
  ) {
    await db.deviceMeta.update("device", { clockCounter: version.counter });
  }
}

export async function mergeRemoteEntity(remote: StoredEntity) {
  await db.transaction("rw", db.deviceMeta, db.entities, db.outbox, async () => {
    await observeRemoteVersion(remote.version);
    const local = await db.entities.get(remote.key);
    if (!local || compareVersions(remote.version, local.version) >= 0) {
      await db.entities.put(remote);
      const pending = await db.outbox.get(remote.key);
      if (pending && compareVersions(remote.version, pending.version) >= 0) {
        await db.outbox.delete(remote.key);
      }
    }
  });
}

export async function mergeRemotePage(remoteEntities: StoredEntity[], cursor: number) {
  await db.transaction(
    "rw",
    db.deviceMeta,
    db.entities,
    db.outbox,
    db.syncMeta,
    async () => {
      for (const remote of remoteEntities) {
        await observeRemoteVersion(remote.version);
        const local = await db.entities.get(remote.key);
        if (!local || compareVersions(remote.version, local.version) >= 0) {
          await db.entities.put(remote);
          const pending = await db.outbox.get(remote.key);
          if (pending && compareVersions(remote.version, pending.version) >= 0) {
            await db.outbox.delete(remote.key);
          }
        }
      }
      await db.syncMeta.update(WORKSPACE_ID, { lastPulledRevision: cursor });
    },
  );
}

export async function acknowledgeOperations(
  acknowledgements: Array<{ operationId: string }>,
) {
  await db.transaction("rw", db.outbox, async () => {
    for (const acknowledgement of acknowledgements) {
      const row = await db.outbox.where("operationId").equals(acknowledgement.operationId).first();
      if (row?.operationId === acknowledgement.operationId) {
        await db.outbox.delete(row.key);
      }
    }
  });
}

/** Queue owned local entities (including tombstones) so Sync now can replace cloud state. */
export async function enqueueFullUpload(
  entityTypes: readonly EntityType[] = OWNED_ENTITY_TYPES,
) {
  const allowed = new Set<string>(entityTypes);
  await db.transaction("rw", db.deviceMeta, db.entities, db.outbox, async () => {
    const entities = (await db.entities.toArray()).filter(
      (row) => row.workspaceId === WORKSPACE_ID && allowed.has(row.entityType),
    );
    const now = Date.now();
    for (const entity of entities) {
      const version = await nextVersion();
      const payload = sanitizePayload(entity.entityType, entity.payload);
      const next: StoredEntity = {
        ...entity,
        version,
        payload,
        serverRevision: 0,
      };
      const operation: SyncOperation = {
        operationId: randomId(),
        key: entity.key,
        workspaceId: WORKSPACE_ID,
        entityType: entity.entityType,
        entityId: entity.entityId,
        version,
        payload,
        deleted: entity.deleted,
        status: "pending",
        attempts: 0,
        lastError: null,
        createdAt: now,
      };
      await db.entities.put(next);
      await db.outbox.put(operation);
    }
  });
  notifyWrite();
}

export async function activeEntities<T extends EntityType>(type: T) {
  const rows = await db.entities
    .where("[workspaceId+entityType]")
    .equals([WORKSPACE_ID, type])
    .toArray();
  return rows.filter((row) => !row.deleted) as StoredEntity<T>[];
}
