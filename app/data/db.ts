import Dexie, { type EntityTable } from "dexie";
import type {
  OutboxEntry,
  StoredCategory,
  StoredEmailMessage,
  StoredLend,
  StoredPaymentMethod,
  StoredPreferences,
  StoredRecurring,
  StoredTransaction,
} from "@/data/model";
import { WORKSPACE_ID, type EntityType } from "@/data/model";

export interface SyncMetaRecord {
  workspaceId: typeof WORKSPACE_ID;
  /** @deprecated Prefer pulledRevisions; kept as max across types. */
  lastPulledRevision: number;
  /** Per-type pull cursors for typed sync endpoints. */
  pulledRevisions: Record<EntityType, number>;
  lastSyncedAt: number | null;
  error: string | null;
  syncing: boolean;
}

export interface DeviceMetaRecord {
  id: "device";
  deviceId: string;
  clockTimestamp: number;
  clockCounter: number;
  bootstrapVersion: number;
  lastPaymentMethodId: string | null;
}

export const EMPTY_PULLED_REVISIONS: Record<EntityType, number> = {
  category: 0,
  paymentMethod: 0,
  transaction: 0,
  recurring: 0,
  lend: 0,
  emailMessage: 0,
  preferences: 0,
};

const TYPED_STORES = {
  categories:
    "&key, entityId, [workspaceId+entityId], [workspaceId+serverRevision]",
  paymentMethods:
    "&key, entityId, [workspaceId+entityId], [workspaceId+serverRevision]",
  transactions:
    "&key, entityId, [workspaceId+entityId], [workspaceId+serverRevision], occurredAt, categoryId",
  recurring:
    "&key, entityId, [workspaceId+entityId], [workspaceId+serverRevision], anchorDate",
  lends:
    "&key, entityId, [workspaceId+entityId], [workspaceId+serverRevision], occurredAt",
  emailMessages:
    "&key, entityId, [workspaceId+entityId], [workspaceId+serverRevision], gmailMessageId, state",
  preferences:
    "&key, entityId, [workspaceId+entityId], [workspaceId+serverRevision]",
  outbox: "&key, &operationId, status, entityType, entityId, createdAt",
  syncMeta: "&workspaceId",
  deviceMeta: "&id",
} as const;

export class DimoDatabase extends Dexie {
  categories!: EntityTable<StoredCategory, "key">;
  paymentMethods!: EntityTable<StoredPaymentMethod, "key">;
  transactions!: EntityTable<StoredTransaction, "key">;
  recurring!: EntityTable<StoredRecurring, "key">;
  lends!: EntityTable<StoredLend, "key">;
  emailMessages!: EntityTable<StoredEmailMessage, "key">;
  preferences!: EntityTable<StoredPreferences, "key">;
  outbox!: EntityTable<OutboxEntry, "key">;
  syncMeta!: EntityTable<SyncMetaRecord, "workspaceId">;
  deviceMeta!: EntityTable<DeviceMetaRecord, "id">;

  constructor(name = "dimo-expenses") {
    super(name);
    // v1: legacy blob entities + payload outbox
    this.version(1).stores({
      entities:
        "&key, [workspaceId+entityType+entityId], [workspaceId+entityType], [workspaceId+serverRevision]",
      outbox:
        "&key, &operationId, status, [workspaceId+entityType+entityId], createdAt",
      syncMeta: "&workspaceId",
      deviceMeta: "&id",
    });

    // v2: typed per-entity stores + dirty-key outbox
    this.version(2)
      .stores({
        ...TYPED_STORES,
        // Keep entities readable during upgrade; cleared after split.
        entities:
          "&key, [workspaceId+entityType+entityId], [workspaceId+entityType], [workspaceId+serverRevision]",
      })
      .upgrade(async (tx) => {
        const entities = await tx.table("entities").toArray();
        for (const row of entities) {
          const {
            key,
            workspaceId,
            entityType,
            entityId,
            version,
            payload,
            deleted,
            serverRevision,
          } = row as {
            key: string;
            workspaceId: string;
            entityType: EntityType;
            entityId: string;
            version: StoredCategory["version"];
            payload: Record<string, unknown>;
            deleted: boolean;
            serverRevision: number;
          };
          const { id: ignoredId, ...fields } = payload;
          void ignoredId;
          const typed = {
            key,
            workspaceId,
            entityId,
            version,
            deleted,
            serverRevision,
            ...fields,
          };
          const tableName =
            entityType === "category"
              ? "categories"
              : entityType === "paymentMethod"
                ? "paymentMethods"
                : entityType === "transaction"
                  ? "transactions"
                  : entityType === "recurring"
                    ? "recurring"
                    : entityType === "lend"
                      ? "lends"
                      : entityType === "emailMessage"
                        ? "emailMessages"
                        : "preferences";
          await tx.table(tableName).put(typed);
        }

        const oldOutbox = await tx.table("outbox").toArray();
        await tx.table("outbox").clear();
        for (const op of oldOutbox) {
          await tx.table("outbox").put({
            key: op.key,
            operationId: op.operationId,
            entityType: op.entityType,
            entityId: op.entityId,
            status: op.status,
            attempts: op.attempts,
            lastError: op.lastError,
            createdAt: op.createdAt,
          });
        }

        const meta = await tx.table("syncMeta").get(WORKSPACE_ID);
        if (meta) {
          const pulled = { ...EMPTY_PULLED_REVISIONS };
          const cursor = Number(meta.lastPulledRevision) || 0;
          for (const type of Object.keys(pulled) as EntityType[]) {
            pulled[type] = cursor;
          }
          await tx.table("syncMeta").put({
            ...meta,
            pulledRevisions: pulled,
          });
        }

        await tx.table("entities").clear();
      });

    // v3: drop legacy entities store from schema
    this.version(3).stores({
      ...TYPED_STORES,
      entities: null,
    });
  }
}

const DB_PREFIX = "dimo-expenses";
let activeUserId: string | null = null;
export let db = new DimoDatabase(`${DB_PREFIX}:unconfigured`);

/** Select a separate local-first database before rendering a user's app. */
export function activateUserDatabase(userId: string) {
  if (activeUserId === userId) return;
  db.close();
  activeUserId = userId;
  db = new DimoDatabase(`${DB_PREFIX}:${encodeURIComponent(userId)}`);
}

/** Wipe every local Dimo IndexedDB database (used on sign-out). */
export async function deleteAllLocalDatabases() {
  const currentName = db.name;
  db.close();
  activeUserId = null;

  if (typeof indexedDB.databases === "function") {
    const databases = await indexedDB.databases();
    const names = databases
      .map((entry) => entry.name)
      .filter((name): name is string => !!name && name.startsWith(DB_PREFIX));
    await Promise.all(names.map((name) => Dexie.delete(name)));
  } else {
    await Dexie.delete(currentName);
  }

  db = new DimoDatabase(`${DB_PREFIX}:unconfigured`);
}
