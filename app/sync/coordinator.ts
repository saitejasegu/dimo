import { ConvexReactClient } from "convex/react";
import { makeFunctionReference } from "convex/server";
import { db } from "@/data/db";
import {
  WORKSPACE_ID,
  entityKey,
  type StoredEntity,
  type SyncOperation,
} from "@/data/model";
import {
  acknowledgeOperations,
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

const pullRef = makeFunctionReference<"query", {
  workspaceId: string;
  afterRevision: number;
  limit: number;
}, PullResult>("sync:pull");
const pushRef = makeFunctionReference<"mutation", {
  workspaceId: string;
  operations: Array<Omit<SyncOperation, "key" | "status" | "attempts" | "lastError" | "createdAt">>;
}, PushResult>("sync:push");
const revisionRef = makeFunctionReference<"query", { workspaceId: string }, number>(
  "sync:currentRevision",
);

export class SyncCoordinator {
  private running: Promise<void> | null = null;
  private requested = false;
  private debounceTimer: ReturnType<typeof setTimeout> | null = null;
  private retryTimer: ReturnType<typeof setTimeout> | null = null;
  private retryAttempt = 0;
  private disposers: Array<() => void> = [];

  constructor(private client: ConvexReactClient) {}

  start() {
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
    this.request();
  }

  stop() {
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

  private async runLoop() {
    while (this.requested) {
      this.requested = false;
      if (!navigator.onLine) {
        await db.syncMeta.update(WORKSPACE_ID, { syncing: false, error: "Offline" });
        return;
      }
      await db.syncMeta.update(WORKSPACE_ID, { syncing: true, error: null });
      try {
        await this.pullAll();
        await this.pushAll();
        await this.pullAll();
        this.retryAttempt = 0;
        if (this.retryTimer) clearTimeout(this.retryTimer);
        await db.syncMeta.update(WORKSPACE_ID, {
          syncing: false,
          error: null,
          lastSyncedAt: Date.now(),
        });
      } catch (error) {
        await this.setError(error);
        this.scheduleRetry();
        return;
      }
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
      const payload = operations.map((op) => ({
        operationId: op.operationId,
        workspaceId: op.workspaceId,
        entityType: op.entityType,
        entityId: op.entityId,
        version: op.version,
        payload: op.payload,
        deleted: op.deleted,
      }));
      try {
        const result = await this.client.mutation(pushRef, {
          workspaceId: WORKSPACE_ID,
          operations: payload,
        });
        await acknowledgeOperations(result.acknowledgements);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        const permanent = /validation|payload|mismatch|unsupported|invalid|at most 50/i.test(message);
        await db.transaction("rw", db.outbox, async () => {
          for (const operation of operations) {
            const current = await db.outbox.get(operation.key);
            if (current?.operationId !== operation.operationId) continue;
            await db.outbox.update(operation.key, {
              attempts: operation.attempts + 1,
              lastError: message,
              status: permanent ? "blocked" : "pending",
            });
          }
        });
        if (!permanent) throw error;
      }
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

export function startSync(client: ConvexReactClient) {
  sharedCoordinator ??= new SyncCoordinator(client);
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
