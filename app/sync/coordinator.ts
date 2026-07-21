import { ConvexReactClient } from "convex/react";
import { makeFunctionReference } from "convex/server";
import { db } from "@/data/db";
import {
  WORKSPACE_ID,
  ALL_CLOUD_ENTITY_TYPES,
  OWNED_ENTITY_TYPES,
  entityKey,
  type CloudEntityType,
  type StoredEntity,
  type SyncOperation,
} from "@/data/model";
import {
  acknowledgeOperations,
  backfillRecurringCurrencies,
  enqueueFullUpload,
  enqueueUnsyncedDefaults,
  mergeRemotePage,
  onLocalWrite,
} from "@/data/repository";

type PullResult = {
  entities: Array<Omit<StoredEntity, "key">>;
  latestRevision: number;
  hasMore: boolean;
};

type PushResult = {
  acknowledgements: Array<{ operationId: string; applied: boolean; revision: number }>;
  latestRevision: number;
};

type ClearResult = {
  deleted: number;
  hasMore: boolean;
};

type PushOperation = Omit<
  SyncOperation,
  "key" | "status" | "attempts" | "lastError" | "createdAt"
>;

const pullRef = makeFunctionReference<"query", {
  workspaceId: string;
  afterRevision: number;
  limit: number;
}, PullResult>("sync:pull");
const pushRef = makeFunctionReference<"mutation", {
  workspaceId: string;
  operations: Array<PushOperation>;
}, PushResult>("sync:push");
const revisionRef = makeFunctionReference<"query", { workspaceId: string }, number>(
  "sync:currentRevision",
);
const ensureProfileRef = makeFunctionReference<
  "mutation",
  { workspaceId: string; name?: string; email?: string },
  { created: boolean; updated: boolean; name: string | null; email: string | null }
>("sync:ensureWorkspaceProfile");
const clearRef = makeFunctionReference<"mutation", {
  workspaceId: string;
  entityTypes: CloudEntityType[];
  limit?: number;
}, ClearResult>("sync:clearWorkspace");

/** Only treat known client/server validation failures as permanent. */
export function isPermanentSyncError(message: string) {
  return /ArgumentValidationError|Payload does not match|Entity ID mismatch|Workspace mismatch|Unsupported workspace|Invalid logical version|Invalid minor-unit amount|Invalid recurring anchor date|A push may contain at most 50/i.test(
    message,
  );
}

function toPushPayload(operations: SyncOperation[]): PushOperation[] {
  return operations.map((op) => ({
    operationId: op.operationId,
    workspaceId: op.workspaceId,
    entityType: op.entityType,
    entityId: op.entityId,
    version: op.version,
    payload: op.payload,
    deleted: op.deleted,
  }));
}

export class SyncCoordinator {
  private running: Promise<void> | null = null;
  private requested = false;
  private fullReplace = false;
  private debounceTimer: ReturnType<typeof setTimeout> | null = null;
  private retryTimer: ReturnType<typeof setTimeout> | null = null;
  private retryAttempt = 0;
  private disposers: Array<() => void> = [];
  private profile: { name?: string; email?: string } = {};
  private started = false;

  constructor(private client: ConvexReactClient) {}

  setProfile(profile: { name?: string; email?: string }) {
    this.profile = {
      name: profile.name?.trim() || undefined,
      email: profile.email?.trim() || undefined,
    };
  }

  /** Push AuthKit name/email onto the workspace row immediately (and on later syncs). */
  async ensureProfile() {
    await this.client.mutation(ensureProfileRef, {
      workspaceId: WORKSPACE_ID,
      name: this.profile.name,
      email: this.profile.email,
    });
  }

  start() {
    if (!this.started) {
      this.started = true;
      this.disposers.push(onLocalWrite(() => this.schedule()));
      const online = () => this.request();
      const focus = () => this.request();
      const visible = () => {
        if (document.visibilityState === "visible") this.request();
      };
      window.addEventListener("online", online);
      window.addEventListener("focus", focus);
      document.addEventListener("visibilitychange", visible);
      this.disposers.push(
        () => window.removeEventListener("online", online),
        () => window.removeEventListener("focus", focus),
        () => document.removeEventListener("visibilitychange", visible),
      );
      const watch = this.client.watchQuery(revisionRef, { workspaceId: WORKSPACE_ID });
      const unsubscribe = watch.onUpdate(() => this.request());
      this.disposers.push(unsubscribe);
    }
    this.request();
  }

  stop() {
    this.started = false;
    for (const dispose of this.disposers.splice(0)) dispose();
    if (this.debounceTimer) clearTimeout(this.debounceTimer);
    if (this.retryTimer) clearTimeout(this.retryTimer);
  }

  schedule() {
    if (this.debounceTimer) clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(() => this.request(), 250);
  }

  request() {
    this.requested = true;
    if (!this.running) {
      this.running = this.runLoop().finally(() => {
        this.running = null;
      });
    }
    return this.running;
  }

  /** Manual Sync now: wipe this app's cloud entity types, then upload the local snapshot. */
  requestFullSync() {
    this.fullReplace = true;
    return this.request();
  }

  private async runLoop() {
    while (this.requested) {
      this.requested = false;
      const replace = this.fullReplace;
      this.fullReplace = false;
      if (!navigator.onLine) {
        await db.syncMeta.update(WORKSPACE_ID, { syncing: false, error: "Offline" });
        return;
      }
      await db.syncMeta.update(WORKSPACE_ID, { syncing: true, error: null });
      try {
        // Backfill workspace name/email for existing rows on every authenticated sync.
        // WorkOS JWTs omit these claims, so pass the AuthKit user profile explicitly.
        await this.ensureProfile();
        if (replace) {
          await backfillRecurringCurrencies();
          await this.clearRemote([...OWNED_ENTITY_TYPES]);
          await db.syncMeta.update(WORKSPACE_ID, { lastPulledRevision: 0 });
          await enqueueFullUpload([...OWNED_ENTITY_TYPES]);
          await this.pushAll();
          await this.pullAll();
        } else {
          await this.pullAll();
          await backfillRecurringCurrencies();
          // Upload bootstrap defaults only if pull left them unsynced (empty
          // workspace). Avoids fresh null-budget seeds overwriting cloud budgets.
          await enqueueUnsyncedDefaults();
          await this.pushAll();
          await this.pullAll();
        }
        this.retryAttempt = 0;
        if (this.retryTimer) clearTimeout(this.retryTimer);
        const blocked = await db.outbox.where("status").equals("blocked").first();
        await db.syncMeta.update(WORKSPACE_ID, {
          syncing: false,
          error: blocked?.lastError ?? null,
          ...(blocked ? {} : { lastSyncedAt: Date.now() }),
        });
      } catch (error) {
        if (replace) this.fullReplace = true;
        await this.setError(error);
        this.scheduleRetry();
        return;
      }
    }
  }

  private async clearRemote(entityTypes: CloudEntityType[]) {
    while (true) {
      const result = await this.client.mutation(clearRef, {
        workspaceId: WORKSPACE_ID,
        entityTypes,
        limit: 100,
      });
      if (!result.hasMore) return;
    }
  }

  private async pullAll() {
    let meta = await db.syncMeta.get(WORKSPACE_ID);
    let cursor = meta?.lastPulledRevision ?? 0;
    while (true) {
      const page = await this.client.query(pullRef, {
        workspaceId: WORKSPACE_ID,
        afterRevision: cursor,
        limit: 100,
      });
      const rows = page.entities.map((row) => ({
        ...row,
        key: entityKey(row.entityType, row.entityId),
      })) as StoredEntity[];
      const pageCursor = rows.length
        ? Math.max(...rows.map((row) => row.serverRevision))
        : page.latestRevision;
      await mergeRemotePage(rows, pageCursor);
      cursor = pageCursor;
      if (!page.hasMore) break;
      meta = await db.syncMeta.get(WORKSPACE_ID);
    }
  }

  private async pushAll() {
    while (true) {
      const operations = await db.outbox.where("status").equals("pending").limit(50).toArray();
      if (!operations.length) return;
      await this.pushBatch(operations);
    }
  }

  private async pushBatch(operations: SyncOperation[]) {
    try {
      const result = await this.client.mutation(pushRef, {
        workspaceId: WORKSPACE_ID,
        operations: toPushPayload(operations),
      });
      await acknowledgeOperations(result.acknowledgements);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (!isPermanentSyncError(message)) {
        await db.transaction("rw", db.outbox, async () => {
          for (const operation of operations) {
            const current = await db.outbox.get(operation.key);
            if (current?.operationId !== operation.operationId) continue;
            await db.outbox.update(operation.key, {
              attempts: operation.attempts + 1,
              lastError: message,
            });
          }
        });
        throw error;
      }
      if (operations.length > 1) {
        const mid = Math.max(1, Math.floor(operations.length / 2));
        await this.pushBatch(operations.slice(0, mid));
        await this.pushBatch(operations.slice(mid));
        return;
      }
      const operation = operations[0];
      await db.outbox.update(operation.key, {
        attempts: operation.attempts + 1,
        lastError: message,
        status: "blocked",
      });
    }
  }

  private async setError(error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    await db.syncMeta.update(WORKSPACE_ID, { syncing: false, error: message });
  }

  private scheduleRetry() {
    if (this.retryTimer) clearTimeout(this.retryTimer);
    const base = Math.min(300_000, 1000 * 2 ** this.retryAttempt++);
    const delay = Math.round(base * (0.75 + Math.random() * 0.5));
    this.retryTimer = setTimeout(() => this.request(), delay);
  }
}

let sharedCoordinator: SyncCoordinator | null = null;

export function startSync(
  client: ConvexReactClient,
  profile?: { name?: string; email?: string },
) {
  sharedCoordinator ??= new SyncCoordinator(client);
  if (profile) sharedCoordinator.setProfile(profile);
  // Kick the workspace profile write immediately on login, then start normal sync.
  void sharedCoordinator.ensureProfile().catch(() => {
    // Auth token may still be attaching; the sync loop retries ensureProfile.
  });
  sharedCoordinator.start();
  return sharedCoordinator;
}

export function stopSync() {
  sharedCoordinator?.stop();
  sharedCoordinator = null;
}

export function requestSync() {
  return sharedCoordinator?.request() ?? Promise.resolve();
}

export function requestFullSync() {
  return sharedCoordinator?.requestFullSync() ?? Promise.resolve();
}

/** Delete every cloud entity for the signed-in owner (paged), including other apps' types. */
export async function clearCloudWorkspace(client: ConvexReactClient) {
  while (true) {
    const result = await client.mutation(clearRef, {
      workspaceId: WORKSPACE_ID,
      entityTypes: [...ALL_CLOUD_ENTITY_TYPES],
      limit: 100,
    });
    if (!result.hasMore) return;
  }
}
