import Dexie, { type EntityTable } from "dexie";
import type { StoredEntity, SyncOperation } from "@/data/model";
import { WORKSPACE_ID } from "@/data/model";

export interface SyncMetaRecord {
  workspaceId: typeof WORKSPACE_ID;
  lastPulledRevision: number;
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

export class DimoDatabase extends Dexie {
  entities!: EntityTable<StoredEntity, "key">;
  outbox!: EntityTable<SyncOperation, "key">;
  syncMeta!: EntityTable<SyncMetaRecord, "workspaceId">;
  deviceMeta!: EntityTable<DeviceMetaRecord, "id">;

  constructor(name = "dimo-expenses") {
    super(name);
    this.version(1).stores({
      entities:
        "&key, [workspaceId+entityType+entityId], [workspaceId+entityType], [workspaceId+serverRevision]",
      outbox:
        "&key, &operationId, status, [workspaceId+entityType+entityId], createdAt",
      syncMeta: "&workspaceId",
      deviceMeta: "&id",
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
