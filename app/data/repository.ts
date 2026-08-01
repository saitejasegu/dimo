import {
  db,
  EMPTY_PULLED_REVISIONS,
  type DeviceMetaRecord,
  type SyncMetaRecord,
} from "@/data/db";
import {
  CASH_PAYMENT_METHOD,
  DEFAULT_CATEGORY_EMOJI,
  DEFAULT_PREFERENCES,
  OWNED_ENTITY_TYPES,
  TOMBSTONE_RETENTION_DAYS,
  WORKSPACE_ID,
  compareVersions,
  entityKey,
  payloadFromStored,
  storedFieldsFromPayload,
  type CategoryEntity,
  type EmailMessageEntity,
  type EntityPayload,
  type EntityPayloadMap,
  type EntityType,
  type LendEntity,
  type LogicalVersion,
  type OutboxEntry,
  type PaymentMethodEntity,
  type PreferencesEntity,
  type RecurringEntity,
  type StoredRow,
  type StoredRowMap,
  type TransactionEntity,
} from "@/data/model";

/**
 * Version 4 replays the cloud snapshot once. Some mobile-web databases pulled
 * lending rows before the `kind` field existed and otherwise keep classifying
 * repayments as money lent.
 *
 * Version 5 replays it again. Databases whose per-type pull cursor for a type was
 * once missing resumed that type from the workspace-wide revision instead of zero,
 * permanently hiding every row of that type written before then; only a replay from
 * zero brings them back.
 */
const BOOTSTRAP_VERSION = 5;

/**
 * Bump when a new legacy-row repair is added, so every client runs it once.
 * The repairs scan whole tables, which is why they no longer run on every sync.
 */
const BACKFILL_VERSION = 1;

/** Types whose rows the repairs inspect; arrival of these re-arms the repairs. */
const BACKFILLED_TYPES: ReadonlySet<string> = new Set(["transaction", "recurring"]);

async function backfillsPending(): Promise<boolean> {
  const device = await db.deviceMeta.get("device");
  return (device?.backfillVersion ?? 0) < BACKFILL_VERSION;
}

async function markBackfillsApplied() {
  await db.deviceMeta.update("device", { backfillVersion: BACKFILL_VERSION });
}

const listeners = new Set<() => void>();

type TypedTable =
  | typeof db.categories
  | typeof db.paymentMethods
  | typeof db.transactions
  | typeof db.recurring
  | typeof db.lends
  | typeof db.emailMessages
  | typeof db.preferences;

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

export function tableForType(entityType: EntityType): TypedTable {
  switch (entityType) {
    case "category":
      return db.categories;
    case "paymentMethod":
      return db.paymentMethods;
    case "transaction":
      return db.transactions;
    case "recurring":
      return db.recurring;
    case "lend":
      return db.lends;
    case "emailMessage":
      return db.emailMessages;
    case "preferences":
      return db.preferences;
  }
}

export async function getStoredRow<T extends EntityType>(
  entityType: T,
  id: string,
): Promise<StoredRowMap[T] | undefined> {
  return (await tableForType(entityType).get(entityKey(entityType, id))) as
    | StoredRowMap[T]
    | undefined;
}

/** All typed tables touched by repository writes. */
function allTypedTables() {
  return [
    db.categories,
    db.paymentMethods,
    db.transactions,
    db.recurring,
    db.lends,
    db.emailMessages,
    db.preferences,
    db.outbox,
    db.deviceMeta,
    db.syncMeta,
  ];
}

/**
 * Tables a versioned write actually touches: the entity's own store, the outbox, and
 * deviceMeta for the logical clock. Scoping the transaction this narrowly means a
 * transaction save no longer blocks reads of every other store.
 */
function writeTables(entityTypes: EntityType[]) {
  const tables = new Set<TypedTable | typeof db.outbox | typeof db.deviceMeta>([
    db.outbox,
    db.deviceMeta,
  ]);
  for (const entityType of entityTypes) tables.add(tableForType(entityType));
  return [...tables];
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

/**
 * Hands out consecutive logical versions from one deviceMeta read/write pair.
 *
 * Per-row clock round-trips dominate bulk writes (a CSV import of 1 000 rows spent
 * ~2 000 IndexedDB ops purely on the clock). Reserving the whole run up front keeps
 * versions strictly increasing with two ops total, which is all last-write-wins needs.
 */
interface VersionRun {
  next: () => LogicalVersion;
}

async function startVersionRun(count: number): Promise<VersionRun> {
  const device = await ensureDevice();
  const now = Date.now();
  const timestamp = Math.max(now, device.clockTimestamp);
  const firstCounter =
    timestamp === device.clockTimestamp ? device.clockCounter + 1 : 0;
  await db.deviceMeta.update("device", {
    clockTimestamp: timestamp,
    clockCounter: firstCounter + Math.max(0, count - 1),
  });
  let issued = 0;
  return {
    next: () => {
      const counter = firstCounter + issued;
      issued += 1;
      return { timestamp, counter, deviceId: device.deviceId };
    },
  };
}

async function nextVersion(): Promise<LogicalVersion> {
  const run = await startVersionRun(1);
  return run.next();
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
      const paymentMethodId = String(value.paymentMethodId ?? "").trim();
      const clean: TransactionEntity = {
        id: value.id,
        name: value.name,
        amountMinor: Math.max(1, Math.round(Number(value.amountMinor) || 0)),
        occurredAt: Math.round(Number(value.occurredAt) || Date.now()),
        categoryId: value.categoryId,
        paymentMethodId: paymentMethodId || CASH_PAYMENT_METHOD.id,
      };
      const currency = String(value.currency ?? "").trim();
      if (currency) clean.currency = currency;
      const sourceCurrency = String(value.sourceCurrency ?? "").trim();
      if (sourceCurrency) {
        clean.sourceCurrency = sourceCurrency;
        clean.sourceAmountMinor = Math.max(1, Math.round(Number(value.sourceAmountMinor) || 0));
        const rate = Number(value.exchangeRate);
        if (Number.isFinite(rate) && rate > 0) clean.exchangeRate = rate;
      }
      return clean as EntityPayloadMap[T];
    }
    case "recurring": {
      const value = payload as RecurringEntity;
      const anchor = String(value.anchorDate ?? "");
      const paymentMethodId = String(value.paymentMethodId ?? "").trim();
      const clean: RecurringEntity = {
        id: value.id,
        name: value.name,
        amountMinor: Math.max(1, Math.round(Number(value.amountMinor) || 0)),
        categoryId: value.categoryId,
        paymentMethodId: paymentMethodId || CASH_PAYMENT_METHOD.id,
        frequency: value.frequency === "yearly" ? "yearly" : "monthly",
        anchorDate: /^\d{4}-\d{2}-\d{2}$/.test(anchor)
          ? anchor
          : new Date().toISOString().slice(0, 10),
        paused: Boolean(value.paused),
      };
      const currency = String(value.currency ?? "").trim();
      if (currency) clean.currency = currency;
      return clean as EntityPayloadMap[T];
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
        purchaseGroupId: optionalString(value.purchaseGroupId),
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

function toStoredRow<T extends EntityType>(
  entityType: T,
  payload: EntityPayloadMap[T],
  version: LogicalVersion,
  deleted: boolean,
  serverRevision: number,
): StoredRowMap[T] {
  const clean = sanitizePayload(entityType, payload);
  const key = entityKey(entityType, clean.id);
  return {
    key,
    workspaceId: WORKSPACE_ID,
    entityId: clean.id,
    version,
    deleted,
    serverRevision,
    ...storedFieldsFromPayload(clean),
  } as unknown as StoredRowMap[T];
}

async function putLocalOnly<T extends EntityType>(
  entityType: T,
  payload: EntityPayloadMap[T],
  deleted = false,
) {
  const device = await ensureDevice();
  const row = toStoredRow(
    entityType,
    payload,
    { timestamp: 0, counter: 0, deviceId: device.deviceId },
    deleted,
    0,
  );
  await tableForType(entityType).put(row as never);
}

async function putInCurrentTransaction<T extends EntityType>(
  entityType: T,
  payload: EntityPayloadMap[T],
  deleted = false,
  clock?: VersionRun,
) {
  const version = clock ? clock.next() : await nextVersion();
  const row = toStoredRow(entityType, payload, version, deleted, 0);
  const operation: OutboxEntry = {
    operationId: randomId(),
    key: row.key,
    entityType,
    entityId: row.entityId,
    status: "pending",
    attempts: 0,
    lastError: null,
    createdAt: Date.now(),
  };
  await tableForType(entityType).put(row as never);
  await db.outbox.put(operation);
}

export async function initializeLocalDatabase() {
  await db.open();
  await db.transaction("rw", allTypedTables(), async () => {
    const device = await ensureDevice();
    const shouldReplayCloudSnapshot = device.bootstrapVersion < BOOTSTRAP_VERSION;
    if (device.bootstrapVersion < BOOTSTRAP_VERSION) {
      if (!(await getStoredRow("paymentMethod", CASH_PAYMENT_METHOD.id))) {
        await putLocalOnly("paymentMethod", CASH_PAYMENT_METHOD);
      }
      if (!(await getStoredRow("preferences", DEFAULT_PREFERENCES.id))) {
        await putLocalOnly("preferences", DEFAULT_PREFERENCES);
      }
      await db.deviceMeta.update("device", { bootstrapVersion: BOOTSTRAP_VERSION });
    }
    const existingMeta = await db.syncMeta.get(WORKSPACE_ID);
    if (!existingMeta) {
      const meta: SyncMetaRecord = {
        workspaceId: WORKSPACE_ID,
        lastPulledRevision: 0,
        pulledRevisions: { ...EMPTY_PULLED_REVISIONS },
        lastSyncedAt: null,
        error: null,
        syncing: false,
      };
      await db.syncMeta.add(meta);
    } else {
      const pulled = {
        ...EMPTY_PULLED_REVISIONS,
        ...(existingMeta.pulledRevisions ?? {}),
      };
      const patch: Partial<SyncMetaRecord> = {};
      // A cursor missing for even one type makes that type resume from the wrong
      // place, so fill the gaps with zero rather than only rebuilding a wholly
      // absent record.
      const complete = (Object.keys(EMPTY_PULLED_REVISIONS) as EntityType[]).every(
        (type) => typeof existingMeta.pulledRevisions?.[type] === "number",
      );
      if (!complete) patch.pulledRevisions = pulled;
      if (shouldReplayCloudSnapshot) {
        patch.lastPulledRevision = 0;
        patch.pulledRevisions = { ...EMPTY_PULLED_REVISIONS };
      }
      if (Object.keys(patch).length > 0) {
        await db.syncMeta.update(WORKSPACE_ID, patch);
      }
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
  await db.transaction("rw", allTypedTables(), async () => {
    for (const { entityType, payload } of defaults) {
      const existing = await getStoredRow(entityType, payload.id);
      if (!existing || existing.deleted || existing.serverRevision > 0) continue;
      if (await db.outbox.get(entityKey(entityType, payload.id))) continue;
      await putInCurrentTransaction(
        entityType,
        payloadFromStored(entityType, existing) as EntityPayloadMap[typeof entityType],
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
  await db.transaction("rw", writeTables([entityType]), async () => {
    await putInCurrentTransaction(entityType, payload);
  });
  notifyWrite();
}

/** Persist a related set of entities atomically, with one sync operation per row. */
export async function saveEntities(
  entities: Array<{ entityType: EntityType; payload: EntityPayload }>,
) {
  if (entities.length === 0) return;
  const types = [...new Set(entities.map((entity) => entity.entityType))];
  await db.transaction("rw", writeTables(types), async () => {
    const clock = await startVersionRun(entities.length);
    for (const entity of entities) {
      await putInCurrentTransaction(entity.entityType, entity.payload, false, clock);
    }
  });
  notifyWrite();
}

/**
 * Give legacy recurring and transaction rows an explicit denomination using the
 * synced account currency. Writing through the normal repository path versions
 * the repair and places it in the outbox so every client converges.
 */
export async function backfillRecurringCurrencies() {
  let updated = 0;
  await db.transaction("rw", allTypedTables(), async () => {
    const preferences = await getStoredRow("preferences", "preferences");
    const accountCurrency =
      preferences && !preferences.deleted
        ? String(preferences.currency || DEFAULT_PREFERENCES.currency)
        : DEFAULT_PREFERENCES.currency;

    for (const entityType of ["recurring", "transaction"] as const) {
      const rows = (await tableForType(entityType).toArray()) as StoredRow[];
      for (const row of rows) {
        if (row.deleted) continue;
        if (String((row as { currency?: string }).currency ?? "").trim()) continue;
        const payload = payloadFromStored(entityType, row as never);
        await putInCurrentTransaction(entityType, {
          ...payload,
          currency: accountCurrency,
        });
        updated += 1;
      }
    }
  });
  if (updated > 0) notifyWrite();
  return updated;
}

/**
 * Repair legacy transaction/recurring rows that omitted paymentMethodId.
 * Uses the account default when present, otherwise Cash, and enqueues the
 * versioned repair so cloud and other clients converge.
 */
export async function backfillMissingPaymentMethodIds() {
  let updated = 0;
  await db.transaction("rw", allTypedTables(), async () => {
    const preferences = await getStoredRow("preferences", "preferences");
    const defaultPaymentMethodId =
      preferences && !preferences.deleted
        ? String(
            (preferences as { defaultPaymentMethodId?: string }).defaultPaymentMethodId ||
              CASH_PAYMENT_METHOD.id,
          ).trim() || CASH_PAYMENT_METHOD.id
        : CASH_PAYMENT_METHOD.id;
    const paymentMethods = (await tableForType("paymentMethod").toArray()) as StoredRow[];
    const activeIds = new Set(
      paymentMethods
        .filter((row) => !row.deleted)
        .map((row) => row.entityId),
    );
    const fallbackId = activeIds.has(defaultPaymentMethodId)
      ? defaultPaymentMethodId
      : activeIds.has(CASH_PAYMENT_METHOD.id)
        ? CASH_PAYMENT_METHOD.id
        : [...activeIds][0] ?? CASH_PAYMENT_METHOD.id;

    for (const entityType of ["transaction", "recurring"] as const) {
      const rows = (await tableForType(entityType).toArray()) as StoredRow[];
      for (const row of rows) {
        if (row.deleted) continue;
        const current = String(
          (row as { paymentMethodId?: string | null }).paymentMethodId ?? "",
        ).trim();
        // Already valid, or already repaired to the fallback (even if the
        // payment-method row is temporarily missing). Rewriting every sync
        // would bump versions forever and leave the UI stuck on "Syncing".
        if (current && (activeIds.has(current) || current === fallbackId)) continue;
        const payload = payloadFromStored(entityType, row as never);
        await putInCurrentTransaction(entityType, {
          ...payload,
          paymentMethodId: fallbackId,
        });
        updated += 1;
      }
    }
  });
  // Intentionally no notifyWrite: this runs inside the sync loop, which pushes
  // the outbox next. Notifying would reschedule another sync and can fight the
  // revision subscription (UI stuck on "Syncing").
  return updated;
}

/**
 * Run the legacy-row repairs at most once per generation.
 *
 * Both repairs scan the transaction and recurring tables end to end. Running them on
 * every sync cycle meant two full scans after every local write. The flag is cleared
 * again by `mergeRemotePage` whenever a pull delivers rows that could be legacy, so
 * data arriving from an older client is still repaired.
 */
export async function runPendingBackfills() {
  if (!(await backfillsPending())) return { currencies: 0, paymentMethods: 0 };
  const currencies = await backfillRecurringCurrencies();
  const paymentMethods = await backfillMissingPaymentMethodIds();
  await markBackfillsApplied();
  return { currencies, paymentMethods };
}

export async function removeEntity<T extends EntityType>(
  entityType: T,
  id: string,
) {
  await removeEntities(entityType, [id]);
}

/**
 * Tombstone many rows of one type in a single transaction.
 *
 * Deleting per id meant one IndexedDB transaction and one live-query invalidation
 * each, so clearing history re-projected and re-rendered the whole app once per row.
 */
export async function removeEntities<T extends EntityType>(
  entityType: T,
  ids: string[],
) {
  const unique = [...new Set(ids)];
  if (unique.length === 0) return;
  let removed = 0;
  await db.transaction("rw", writeTables([entityType]), async () => {
    const rows = await Promise.all(
      unique.map((id) => getStoredRow(entityType, id)),
    );
    const live = rows.filter((row) => row && !row.deleted);
    if (live.length === 0) return;
    const clock = await startVersionRun(live.length);
    for (const row of live) {
      await putInCurrentTransaction(
        entityType,
        payloadFromStored(entityType, row!) as EntityPayloadMap[T],
        true,
        clock,
      );
    }
    removed = live.length;
  });
  if (removed > 0) notifyWrite();
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

export async function mergeRemoteRow<T extends EntityType>(
  entityType: T,
  remote: StoredRowMap[T],
) {
  await db.transaction("rw", allTypedTables(), async () => {
    await observeRemoteVersion(remote.version);
    const local = await getStoredRow(entityType, remote.entityId);
    if (!local || compareVersions(remote.version, local.version) >= 0) {
      await tableForType(entityType).put(remote as never);
      const pending = await db.outbox.get(remote.key);
      if (pending) {
        if (!local || compareVersions(remote.version, local.version) >= 0) {
          await db.outbox.delete(remote.key);
        }
      }
    }
  });
}

export async function mergeRemotePage<T extends EntityType>(
  entityType: T,
  remoteRows: Array<StoredRowMap[T]>,
  cursor: number,
) {
  await db.transaction("rw", allTypedTables(), async () => {
    let merged = 0;
    for (const remote of remoteRows) {
      await observeRemoteVersion(remote.version);
      const local = await getStoredRow(entityType, remote.entityId);
      if (!local || compareVersions(remote.version, local.version) >= 0) {
        await tableForType(entityType).put(remote as never);
        merged += 1;
        const pending = await db.outbox.get(remote.key);
        if (pending) await db.outbox.delete(remote.key);
      }
    }
    // Rows just arrived that the legacy repairs inspect — re-arm them so data written
    // by an older client is still normalized, without scanning on every sync.
    if (merged > 0 && BACKFILLED_TYPES.has(entityType)) {
      await db.deviceMeta.update("device", { backfillVersion: 0 });
    }
    const meta = await db.syncMeta.get(WORKSPACE_ID);
    const pulled = {
      ...EMPTY_PULLED_REVISIONS,
      ...(meta?.pulledRevisions ?? {}),
      [entityType]: cursor,
    };
    const lastPulledRevision = Math.max(
      meta?.lastPulledRevision ?? 0,
      ...Object.values(pulled),
    );
    await db.syncMeta.update(WORKSPACE_ID, {
      pulledRevisions: pulled,
      lastPulledRevision,
    });
  });
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
  await db.transaction("rw", allTypedTables(), async () => {
    const now = Date.now();
    for (const entityType of allowed) {
      const type = entityType as EntityType;
      const rows = (await tableForType(type).toArray()) as StoredRow[];
      for (const entity of rows) {
        if (entity.workspaceId !== WORKSPACE_ID) continue;
        const version = await nextVersion();
        const payload = sanitizePayload(
          type,
          payloadFromStored(type, entity as never),
        );
        const next = toStoredRow(type, payload, version, entity.deleted, 0);
        const operation: OutboxEntry = {
          operationId: randomId(),
          key: entity.key,
          entityType: type,
          entityId: entity.entityId,
          status: "pending",
          attempts: 0,
          lastError: null,
          createdAt: now,
        };
        await tableForType(type).put(next as never);
        await db.outbox.put(operation);
      }
    }
  });
  notifyWrite();
}

/**
 * Interval between retention sweeps. The sweep must scan every table — IndexedDB
 * cannot index a boolean, so `deleted` is not queryable — and it only ever collects
 * rows that crossed a multi-day threshold. Running it per sync cycle (i.e. after every
 * local write) bought nothing, so it is throttled instead.
 */
const TOMBSTONE_SWEEP_INTERVAL_MS = 6 * 60 * 60 * 1000;
let lastTombstoneSweepAt = 0;

/** True when a retention sweep is due; call before `purgeExpiredTombstones`. */
export function tombstoneSweepDue(now = Date.now()) {
  return now - lastTombstoneSweepAt >= TOMBSTONE_SWEEP_INTERVAL_MS;
}

/**
 * Hard-delete local tombstones past the private retention window.
 * Skips rows that still have an unacked outbox operation.
 */
export async function purgeExpiredTombstones(now = Date.now()) {
  lastTombstoneSweepAt = now;
  const cutoff = now - TOMBSTONE_RETENTION_DAYS * 24 * 60 * 60 * 1000;
  let purged = 0;
  await db.transaction("rw", allTypedTables(), async () => {
    for (const entityType of ALL_ENTITY_TYPES) {
      const rows = (await tableForType(entityType).toArray()) as StoredRow[];
      for (const row of rows) {
        if (!row.deleted) continue;
        if (row.version.timestamp >= cutoff) continue;
        const pending = await db.outbox.get(row.key);
        if (pending) continue;
        await tableForType(entityType).delete(row.key);
        purged += 1;
      }
    }
  });
  return purged;
}

const ALL_ENTITY_TYPES: EntityType[] = [
  "category",
  "paymentMethod",
  "transaction",
  "recurring",
  "lend",
  "emailMessage",
  "preferences",
];

export async function activeEntities<T extends EntityType>(type: T) {
  const rows = (await tableForType(type).toArray()) as StoredRowMap[T][];
  return rows.filter((row) => !row.deleted);
}

/** Flatten all typed stores for UI hydration (includes tombstones). */
export async function allStoredRows(): Promise<
  Array<{ entityType: EntityType; row: StoredRow }>
> {
  const result: Array<{ entityType: EntityType; row: StoredRow }> = [];
  for (const entityType of ALL_ENTITY_TYPES) {
    const rows = (await tableForType(entityType).toArray()) as StoredRow[];
    for (const row of rows) result.push({ entityType, row });
  }
  return result;
}

/** Build a typed push operation from the current stored row + outbox entry. */
export async function buildPushOperation(entry: OutboxEntry) {
  const row = await getStoredRow(entry.entityType, entry.entityId);
  if (!row) return null;
  const fields = storedFieldsFromPayload(
    payloadFromStored(entry.entityType, row as never),
  );
  return {
    operationId: entry.operationId,
    workspaceId: WORKSPACE_ID,
    entityId: row.entityId,
    version: row.version,
    deleted: row.deleted,
    ...fields,
  };
}

export { ALL_ENTITY_TYPES };
