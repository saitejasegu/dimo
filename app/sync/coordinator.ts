import { ConvexReactClient } from "convex/react";
import { makeFunctionReference, type FunctionReference } from "convex/server";
import { db, EMPTY_PULLED_REVISIONS, type SyncMetaRecord } from "@/data/db";
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
  WEB_ENTITY_TYPES,
  acknowledgeOperations,
  buildPushOperations,
  enqueueFullUpload,
  enqueueUnsyncedDefaults,
  mergeRemotePage,
  onLocalWrite,
  purgeExpiredTombstones,
  runPendingBackfills,
  tombstoneSweepDue,
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
  includeSharedLends?: boolean;
}, ClearResult>("syncTyped:clearWorkspace");

/** Only treat known client/server validation failures as permanent. */
export function isPermanentSyncError(message: string) {
  return /ArgumentValidationError|Payload does not match|Entity ID mismatch|Workspace mismatch|Unsupported workspace|Invalid logical version|Invalid minor-unit amount|Invalid recurring anchor date|A push may contain at most 50|Not a member of this lending connection|Unknown lending connection|Lend id collides/i.test(
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

/**
 * Where a pull for one entity type resumes. A missing entry means the type was never
 * pulled, so it must restart at zero: `lastPulledRevision` is the maximum across every
 * type, and resuming from it skips every row of this type written before that point.
 */
export function pullCursorFor(
  meta: Pick<SyncMetaRecord, "pulledRevisions"> | undefined,
  entityType: EntityType,
) {
  const cursor = meta?.pulledRevisions?.[entityType];
  return typeof cursor === "number" && Number.isFinite(cursor) ? cursor : 0;
}

/** Tracks whether a push run left the client caught up without pulling again. */
interface PushTracker {
  /** Revision the client is known to hold everything up to, or null if unknown. */
  caughtUp: number | null;
  /** Something other than our own accepted writes may have changed on the server. */
  needsPull: boolean;
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
  private profileEnsured = false;
  private started = false;
  /** Latest workspace revision from the live subscription. */
  private remoteRevision: number | undefined;
  /**
   * Workspace revision this session has provably pulled everything up to. Kept in
   * memory so every session starts with one full pull; afterwards a cycle only pulls
   * when the server has moved past it.
   */
  private caughtUpRevision: number | null = null;

  constructor(private client: ConvexReactClient) {}

  setProfile(profile: { name?: string; email?: string }) {
    const next = {
      name: profile.name?.trim() || undefined,
      email: profile.email?.trim() || undefined,
    };
    if (next.name !== this.profile.name || next.email !== this.profile.email) {
      this.profileEnsured = false;
    }
    this.profile = next;
  }

  /** Push AuthKit name/email onto the workspace row (once per session and profile). */
  async ensureProfile() {
    await this.client.mutation(ensureProfileRef, {
      workspaceId: WORKSPACE_ID,
      name: this.profile.name,
      email: this.profile.email,
    });
    this.profileEnsured = true;
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
      // Match iOS: only sync when the server revision is ahead of what we have
      // pulled. Re-emitting the current revision on reconnect would otherwise
      // loop forever and leave the UI stuck on "Syncing".
      const unsubscribe = watch.onUpdate(() => {
        this.remoteRevisionChanged(watch.localQueryResult());
      });
      this.disposers.push(unsubscribe);
    }
    this.request();
  }

  private remoteRevisionChanged(revision: number | undefined) {
    if (typeof revision !== "number" || !Number.isFinite(revision)) return;
    this.remoteRevision = revision;
    if (this.caughtUpRevision === null || revision > this.caughtUpRevision) this.request();
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

  /** Whether the server may hold rows this session has not pulled yet. */
  private pullNeeded() {
    return (
      this.caughtUpRevision === null ||
      this.remoteRevision === undefined ||
      this.remoteRevision > this.caughtUpRevision
    );
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
      // Focus, visibility and revision re-emits land here constantly. With nothing to
      // pull and nothing queued the cycle has no work, so skip it without touching
      // the network or flashing "Syncing".
      if (
        !replace &&
        this.profileEnsured &&
        !this.pullNeeded() &&
        (await db.outbox.where("status").equals("pending").count()) === 0
      ) {
        continue;
      }
      await db.syncMeta.update(WORKSPACE_ID, { syncing: true, error: null });
      try {
        if (!this.profileEnsured) await this.ensureProfile();
        if (replace) {
          await runPendingBackfills();
          await this.clearRemote([...OWNED_ENTITY_TYPES]);
          await db.syncMeta.update(WORKSPACE_ID, {
            lastPulledRevision: 0,
            pulledRevisions: { ...EMPTY_PULLED_REVISIONS },
          });
          this.caughtUpRevision = null;
          await enqueueFullUpload([...OWNED_ENTITY_TYPES]);
          await this.pushAll();
          await this.pullAll();
        } else {
          // Pull before enqueueing bootstrap defaults so a fresh client cannot
          // overwrite existing cloud data.
          if (this.pullNeeded()) await this.pullAll();
          await runPendingBackfills();
          await enqueueUnsyncedDefaults();
          const pushed = await this.pushAll();
          if (pushed.needsPull) await this.pullAll();
          else this.caughtUpRevision = pushed.caughtUp;
        }
        this.retryAttempt = 0;
        if (this.retryTimer) clearTimeout(this.retryTimer);
        if (tombstoneSweepDue()) await purgeExpiredTombstones();
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

  /**
   * Pull every web type concurrently: they are independent cursors, and running them
   * one after another made each cycle wait on seven sequential round-trips. Each type
   * is complete up to the workspace revision its final page reported, so the lowest of
   * those is a safe caught-up mark.
   */
  private async pullAll() {
    const completeThrough = await Promise.all(
      WEB_ENTITY_TYPES.map((entityType) => this.pullType(entityType)),
    );
    this.caughtUpRevision = Math.min(...completeThrough);
  }

  /** Pull one type to the end; returns the workspace revision its last page saw. */
  private async pullType(entityType: EntityType): Promise<number> {
    const meta = await db.syncMeta.get(WORKSPACE_ID);
    let cursor = pullCursorFor(meta, entityType);
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
      if (!page.hasMore) return page.latestRevision;
    }
  }

  private async pushAll(): Promise<PushTracker> {
    const tracker: PushTracker = { caughtUp: this.caughtUpRevision, needsPull: false };
    while (true) {
      const pending = await db.outbox.where("status").equals("pending").toArray();
      if (!pending.length) return tracker;

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
          await this.pushBatch(entityType, batch, tracker);
          pushedAny = true;
        }
      }
      if (!pushedAny) return tracker;
    }
  }

  private async pushBatch(
    entityType: EntityType,
    operations: OutboxEntry[],
    tracker: PushTracker,
  ) {
    const wireOps = await buildPushOperations(entityType, operations);
    if (!wireOps.length) {
      await db.outbox.bulkDelete(operations.map((entry) => entry.key));
      return;
    }
    try {
      const result = (await this.client.mutation(PUSH_REF[entityType], {
        workspaceId: WORKSPACE_ID,
        operations: wireOps,
      })) as PushResult;
      await acknowledgeOperations(entityType, result.acknowledgements);
      // The server numbers accepted writes consecutively from its current revision. If
      // that run starts exactly where this client was caught up and every operation
      // was applied, nobody else wrote in between and there is nothing to pull back.
      const applied = result.acknowledgements.filter((ack) => ack.applied).length;
      if (
        applied === result.acknowledgements.length &&
        tracker.caughtUp !== null &&
        result.latestRevision - applied === tracker.caughtUp
      ) {
        tracker.caughtUp = result.latestRevision;
      } else {
        tracker.needsPull = true;
      }
    } catch (error) {
      tracker.needsPull = true;
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
        await this.pushBatch(entityType, operations.slice(0, mid), tracker);
        await this.pushBatch(entityType, operations.slice(mid), tracker);
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
  // The first sync cycle upserts the profile before pulling.
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

/** Delete every cloud entity for the signed-in owner (paged), including other
 * apps' types. Account deletion only: also removes lends shared with other
 * accounts and revokes those connections. */
export async function clearCloudWorkspace(client: ConvexReactClient) {
  while (true) {
    const result = await client.mutation(clearRef, {
      workspaceId: WORKSPACE_ID,
      entityTypes: [...ALL_CLOUD_ENTITY_TYPES],
      limit: 100,
      includeSharedLends: true,
    });
    if (!result.hasMore) return;
  }
}
