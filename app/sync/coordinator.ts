import { ConvexReactClient } from "convex/react";
import { makeFunctionReference, type FunctionReference } from "convex/server";
import { db, EMPTY_PULLED_REVISIONS } from "@/data/db";
import {
  WORKSPACE_ID,
  ALL_CLOUD_ENTITY_TYPES,
  OWNED_ENTITY_TYPES,
  entityKey,
  type CloudEntityType,
  type EntityType,
  type LogicalVersion,
  type OutboxEntry,
  type StoredRowMap,
} from "@/data/model";
import {
  ALL_ENTITY_TYPES,
  acknowledgeOperations,
  backfillRecurringCurrencies,
  buildPushOperation,
  enqueueFullUpload,
  enqueueUnsyncedDefaults,
  mergeRemotePage,
  onLocalWrite,
  purgeExpiredTombstones,
} from "@/data/repository";

type PullPage = {
  entities: Array<Record<string, unknown>>;
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

type PullArgs = {
  workspaceId: string;
  afterRevision: number;
  limit: number;
};

const PUSH_REF: Record<EntityType, FunctionReference<"mutation">> = {
  category: makeFunctionReference<"mutation">("syncTyped:pushCategories"),
  paymentMethod: makeFunctionReference<"mutation">("syncTyped:pushPaymentMethods"),
  transaction: makeFunctionReference<"mutation">("syncTyped:pushTransactions"),
  recurring: makeFunctionReference<"mutation">("syncTyped:pushRecurring"),
  lend: makeFunctionReference<"mutation">("syncTyped:pushLends"),
  emailMessage: makeFunctionReference<"mutation">("syncTyped:pushEmailMessages"),
  preferences: makeFunctionReference<"mutation">("syncTyped:pushPreferences"),
};

const PULL_REF: Record<
  EntityType,
  FunctionReference<"query", "public", PullArgs, PullPage>
> = {
  category: makeFunctionReference<"query", PullArgs, PullPage>("syncTyped:pullCategories"),
  paymentMethod: makeFunctionReference<"query", PullArgs, PullPage>(
    "syncTyped:pullPaymentMethods",
  ),
  transaction: makeFunctionReference<"query", PullArgs, PullPage>(
    "syncTyped:pullTransactions",
  ),
  recurring: makeFunctionReference<"query", PullArgs, PullPage>("syncTyped:pullRecurring"),
  lend: makeFunctionReference<"query", PullArgs, PullPage>("syncTyped:pullLends"),
  emailMessage: makeFunctionReference<"query", PullArgs, PullPage>(
    "syncTyped:pullEmailMessages",
  ),
  preferences: makeFunctionReference<"query", PullArgs, PullPage>(
    "syncTyped:pullPreferences",
  ),
};

const revisionRef = makeFunctionReference<"query", { workspaceId: string }, number>(
  "syncTyped:currentRevision",
);
const ensureProfileRef = makeFunctionReference<
  "mutation",
  { workspaceId: string; name?: string; email?: string },
  { created: boolean; updated: boolean; name: string | null; email: string | null }
>("syncTyped:ensureWorkspaceProfile");
const clearRef = makeFunctionReference<"mutation", {
  workspaceId: string;
  entityTypes: CloudEntityType[];
  limit?: number;
}, ClearResult>("syncTyped:clearWorkspace");

/** Only treat known client/server validation failures as permanent. */
export function isPermanentSyncError(message: string) {
  return /ArgumentValidationError|Payload does not match|Entity ID mismatch|Workspace mismatch|Unsupported workspace|Invalid logical version|Invalid minor-unit amount|Invalid recurring anchor date|A push may contain at most 50/i.test(
    message,
  );
}

function toStoredFromPull<T extends EntityType>(
  entityType: T,
  row: Record<string, unknown>,
): StoredRowMap[T] {
  const entityId = String(row.entityId);
  const fields = { ...row };
  delete fields.workspaceId;
  delete fields.entityId;
  const version = fields.version as LogicalVersion;
  const deleted = Boolean(fields.deleted);
  const serverRevision = Number(fields.serverRevision) || 0;
  delete fields.version;
  delete fields.deleted;
  delete fields.serverRevision;
  return {
    key: entityKey(entityType, entityId),
    workspaceId: WORKSPACE_ID,
    entityId,
    version,
    deleted,
    serverRevision,
    ...fields,
  } as StoredRowMap[T];
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
        await this.ensureProfile();
        if (replace) {
          await backfillRecurringCurrencies();
          await this.clearRemote([...OWNED_ENTITY_TYPES]);
          await db.syncMeta.update(WORKSPACE_ID, {
            lastPulledRevision: 0,
            pulledRevisions: { ...EMPTY_PULLED_REVISIONS },
          });
          await enqueueFullUpload([...OWNED_ENTITY_TYPES]);
          await this.pushAll();
          await this.pullAll();
        } else {
          await this.pullAll();
          await backfillRecurringCurrencies();
          await enqueueUnsyncedDefaults();
          await this.pushAll();
          await this.pullAll();
        }
        this.retryAttempt = 0;
        if (this.retryTimer) clearTimeout(this.retryTimer);
        await purgeExpiredTombstones();
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
    for (const entityType of ALL_ENTITY_TYPES) {
      await this.pullType(entityType);
    }
  }

  private async pullType(entityType: EntityType) {
    let meta = await db.syncMeta.get(WORKSPACE_ID);
    let cursor =
      meta?.pulledRevisions?.[entityType] ?? meta?.lastPulledRevision ?? 0;
    while (true) {
      const page = (await this.client.query(PULL_REF[entityType], {
        workspaceId: WORKSPACE_ID,
        afterRevision: cursor,
        limit: 100,
      })) as PullPage;
      const rows = page.entities.map((row) => toStoredFromPull(entityType, row));
      const pageCursor = rows.length
        ? Math.max(...rows.map((row) => row.serverRevision))
        : page.latestRevision;
      await mergeRemotePage(entityType, rows as never, pageCursor);
      cursor = pageCursor;
      if (!page.hasMore) break;
      meta = await db.syncMeta.get(WORKSPACE_ID);
    }
  }

  private async pushAll() {
    while (true) {
      const pending = await db.outbox.where("status").equals("pending").toArray();
      if (!pending.length) return;

      // Group by type so each batch hits one typed endpoint.
      const byType = new Map<EntityType, OutboxEntry[]>();
      for (const op of pending) {
        const list = byType.get(op.entityType) ?? [];
        list.push(op);
        byType.set(op.entityType, list);
      }

      let pushedAny = false;
      for (const [entityType, ops] of byType) {
        // Cap each typed batch at 50.
        for (let i = 0; i < ops.length; i += 50) {
          const batch = ops.slice(i, i + 50);
          await this.pushBatch(entityType, batch);
          pushedAny = true;
        }
      }
      if (!pushedAny) return;
    }
  }

  private async pushBatch(entityType: EntityType, operations: OutboxEntry[]) {
    const wireOps = [];
    for (const entry of operations) {
      const op = await buildPushOperation(entry);
      if (op) wireOps.push(op);
    }
    if (!wireOps.length) {
      for (const entry of operations) await db.outbox.delete(entry.key);
      return;
    }
    try {
      const result = (await this.client.mutation(PUSH_REF[entityType], {
        workspaceId: WORKSPACE_ID,
        operations: wireOps,
      })) as PushResult;
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
        await this.pushBatch(entityType, operations.slice(0, mid));
        await this.pushBatch(entityType, operations.slice(mid));
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
