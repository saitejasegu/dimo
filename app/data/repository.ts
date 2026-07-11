import { db, type DeviceMetaRecord } from "@/data/db";
import {
  CASH_PAYMENT_METHOD,
  DEFAULT_CATEGORY_ENTITIES,
  DEFAULT_PREFERENCES,
  WORKSPACE_ID,
  compareVersions,
  entityKey,
  type CategoryEntity,
  type EntityPayloadMap,
  type EntityType,
  type LogicalVersion,
  type StoredEntity,
  type SyncOperation,
} from "@/data/model";

const BOOTSTRAP_VERSION = 2;
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

async function putInCurrentTransaction<T extends EntityType>(
  entityType: T,
  payload: EntityPayloadMap[T],
  deleted = false,
) {
  const version = await nextVersion();
  const key = entityKey(entityType, payload.id);
  const entity: StoredEntity<T> = {
    key,
    workspaceId: WORKSPACE_ID,
    entityType,
    entityId: payload.id,
    version,
    payload,
    deleted,
    serverRevision: 0,
  };
  const operation: SyncOperation<T> = {
    operationId: randomId(), key, workspaceId: WORKSPACE_ID,
    entityType, entityId: payload.id, version, payload, deleted,
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
    if (device.bootstrapVersion < BOOTSTRAP_VERSION) {
      for (const category of DEFAULT_CATEGORY_ENTITIES) {
        const key = entityKey("category", category.id);
        const existing = await db.entities.get(key);
        if (!existing) {
          await putInCurrentTransaction("category", category);
          continue;
        }
        if (existing.deleted) continue;
        const payload = existing.payload as CategoryEntity & { emoji?: string };
        if (!payload.emoji) {
          await putInCurrentTransaction("category", {
            ...payload,
            emoji: category.emoji,
          });
        }
      }
      if (!(await db.entities.get(entityKey("paymentMethod", CASH_PAYMENT_METHOD.id)))) {
        await putInCurrentTransaction("paymentMethod", CASH_PAYMENT_METHOD);
      }
      if (!(await db.entities.get(entityKey("preferences", DEFAULT_PREFERENCES.id)))) {
        await putInCurrentTransaction("preferences", DEFAULT_PREFERENCES);
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
    }
  });
  if (typeof navigator !== "undefined") {
    void navigator.storage?.persist?.().catch(() => false);
  }
  notifyWrite();
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

export async function activeEntities<T extends EntityType>(type: T) {
  const rows = await db.entities
    .where("[workspaceId+entityType]")
    .equals([WORKSPACE_ID, type])
    .toArray();
  return rows.filter((row) => !row.deleted) as StoredEntity<T>[];
}
