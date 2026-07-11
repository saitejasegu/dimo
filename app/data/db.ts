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

let activeUserId: string | null = null;
export let db = new DimoDatabase("dimo-expenses:unconfigured");

/** Select a separate local-first database before rendering a user's app. */
export function activateUserDatabase(userId: string) {
  if (activeUserId === userId) return;
  db.close();
  activeUserId = userId;
  db = new DimoDatabase(`dimo-expenses:${encodeURIComponent(userId)}`);
}
