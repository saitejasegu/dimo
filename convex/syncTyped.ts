import { mutationGeneric, queryGeneric } from "convex/server";
import { v } from "convex/values";
import {
  clearEntityTypeBoth,
  compareVersions,
  getTypedRow,
  writeTypedAndMirror,
  type Version,
} from "./compat";
import type { EntityTypeName } from "./values";
import {
  categoryOperationValidator,
  emailMessageOperationValidator,
  entityTypeValidator,
  lendOperationValidator,
  paymentMethodOperationValidator,
  preferencesOperationValidator,
  recurringOperationValidator,
  transactionOperationValidator,
} from "./values";

/* eslint-disable @typescript-eslint/no-explicit-any */

type AuthIdentity = {
  tokenIdentifier: string;
  name?: string;
  email?: string;
};

async function requireIdentity(ctx: {
  auth: { getUserIdentity(): Promise<AuthIdentity | null> };
}) {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) throw new Error("Not authenticated");
  return identity;
}

function profileFromPreferences(fields: Record<string, unknown>) {
  const name = typeof fields.profileName === "string" ? fields.profileName.trim() : "";
  const email = typeof fields.profileEmail === "string" ? fields.profileEmail.trim() : "";
  return {
    ...(name ? { name } : {}),
    ...(email ? { email } : {}),
  };
}

function profileFromIdentity(identity: AuthIdentity) {
  const name = identity.name?.trim() ?? "";
  const email = identity.email?.trim() ?? "";
  return {
    ...(name ? { name } : {}),
    ...(email ? { email } : {}),
  };
}

async function loadWorkspace(ctx: { db: any }, ownerId: string, workspaceId: string) {
  return await ctx.db
    .query("workspaces")
    .withIndex("by_owner_and_workspace", (q: any) =>
      q.eq("ownerId", ownerId).eq("workspaceId", workspaceId),
    )
    .unique();
}

async function persistWorkspace(
  ctx: { db: any },
  workspace: any,
  ownerId: string,
  workspaceId: string,
  revision: number,
  identity: AuthIdentity,
  profileUpdate: { name?: string; email?: string },
) {
  const identityProfile = profileFromIdentity(identity);
  const workspaceProfile = {
    ...identityProfile,
    ...profileUpdate,
  };

  if (!workspace) {
    const id = await ctx.db.insert("workspaces", {
      ownerId,
      workspaceId,
      revision,
      ...workspaceProfile,
    });
    return await ctx.db.get(id);
  }

  const patch: { revision?: number; name?: string; email?: string } = {};
  if (workspace.revision !== revision) patch.revision = revision;
  if (workspaceProfile.name && workspaceProfile.name !== workspace.name) {
    patch.name = workspaceProfile.name;
  }
  if (workspaceProfile.email && workspaceProfile.email !== workspace.email) {
    patch.email = workspaceProfile.email;
  }
  if (!workspace.name && identityProfile.name) patch.name = identityProfile.name;
  if (!workspace.email && identityProfile.email) patch.email = identityProfile.email;
  if (Object.keys(patch).length > 0) {
    await ctx.db.patch(workspace._id, patch);
  }
  return workspace;
}

type TypedOpBase = {
  operationId: string;
  workspaceId: string;
  entityId: string;
  version: Version;
  deleted: boolean;
};

function assertVersion(version: Version) {
  if (!Number.isInteger(version.timestamp) || !Number.isInteger(version.counter)) {
    throw new Error("Invalid logical version");
  }
}

function assertAmountMinor(amountMinor: unknown) {
  if (!Number.isInteger(amountMinor) || Number(amountMinor) <= 0) {
    throw new Error("Invalid minor-unit amount");
  }
}

function assertAnchorDate(anchorDate: unknown) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(anchorDate))) {
    throw new Error("Invalid recurring anchor date");
  }
}

async function pushTypedBatch<T extends TypedOpBase>(
  ctx: { db: any; auth: { getUserIdentity(): Promise<AuthIdentity | null> } },
  workspaceId: string,
  operations: T[],
  entityType: EntityTypeName,
  toTypedFields: (op: T) => Record<string, unknown>,
  options?: {
    validate?: (op: T) => void;
    onApplied?: (op: T) => void;
  },
) {
  const identity = await requireIdentity(ctx);
  const ownerId = identity.tokenIdentifier;
  if (workspaceId !== "global") throw new Error("Unsupported workspace");
  if (operations.length > 50) throw new Error("A push may contain at most 50 operations");

  const workspace = await loadWorkspace(ctx, ownerId, workspaceId);
  let revision = workspace?.revision ?? 0;
  const acknowledgements: Array<{
    operationId: string;
    applied: boolean;
    revision: number;
  }> = [];
  let profileUpdate: { name?: string; email?: string } = {};

  for (const operation of operations) {
    if (operation.workspaceId !== workspaceId) throw new Error("Workspace mismatch");
    assertVersion(operation.version);
    options?.validate?.(operation);

    const current = await getTypedRow(
      ctx,
      entityType,
      ownerId,
      workspaceId,
      operation.entityId,
    );
    const applied =
      !current || compareVersions(operation.version, current.version as Version) > 0;
    if (applied) {
      revision += 1;
      const typedRow = {
        ownerId,
        workspaceId,
        entityId: operation.entityId,
        version: operation.version,
        deleted: operation.deleted,
        revision,
        ...toTypedFields(operation),
      };
      await writeTypedAndMirror(ctx, entityType, typedRow);
      if (entityType === "preferences" && !operation.deleted) {
        profileUpdate = {
          ...profileUpdate,
          ...profileFromPreferences(toTypedFields(operation)),
        };
      }
      options?.onApplied?.(operation);
    }
    acknowledgements.push({
      operationId: operation.operationId,
      applied,
      revision: applied ? revision : ((current?.revision as number | undefined) ?? revision),
    });
  }

  await persistWorkspace(
    ctx,
    workspace,
    ownerId,
    workspaceId,
    revision,
    identity,
    profileUpdate,
  );
  return { acknowledgements, latestRevision: revision };
}

async function pullTypedPage(
  ctx: { db: any; auth: { getUserIdentity(): Promise<AuthIdentity | null> } },
  table: string,
  workspaceId: string,
  afterRevision: number,
  limit: number,
  mapRow: (row: any) => Record<string, unknown>,
) {
  const identity = await requireIdentity(ctx);
  const ownerId = identity.tokenIdentifier;
  if (workspaceId !== "global") throw new Error("Unsupported workspace");
  const take = Math.max(1, Math.min(200, Math.floor(limit)));
  const rows = await ctx.db
    .query(table)
    .withIndex("by_owner_workspace_revision", (q: any) =>
      q
        .eq("ownerId", ownerId)
        .eq("workspaceId", workspaceId)
        .gt("revision", afterRevision),
    )
    .take(take + 1);
  const entities = rows.slice(0, take).map(mapRow);
  const workspace = await loadWorkspace(ctx, ownerId, workspaceId);
  return {
    entities,
    latestRevision: workspace?.revision ?? 0,
    hasMore: rows.length > take,
  };
}

function mapCommon(row: any) {
  return {
    workspaceId: row.workspaceId as string,
    entityId: row.entityId as string,
    version: row.version as Version,
    deleted: row.deleted as boolean,
    serverRevision: row.revision as number,
  };
}

// --- Categories ---

export const pushCategories = mutationGeneric({
  args: {
    workspaceId: v.string(),
    operations: v.array(categoryOperationValidator),
  },
  handler: async (ctx, { workspaceId, operations }) =>
    pushTypedBatch(ctx, workspaceId, operations, "category", (op) => ({
      name: op.name,
      ...(op.emoji !== undefined ? { emoji: op.emoji } : {}),
      monthlyBudgetMinor: op.monthlyBudgetMinor,
      tint: op.tint,
      sortOrder: op.sortOrder,
      system: op.system,
    })),
});

export const pullCategories = queryGeneric({
  args: {
    workspaceId: v.string(),
    afterRevision: v.number(),
    limit: v.number(),
  },
  handler: async (ctx, args) =>
    pullTypedPage(
      ctx,
      "categories",
      args.workspaceId,
      args.afterRevision,
      args.limit,
      (row) => ({
        ...mapCommon(row),
        name: row.name,
        emoji: row.emoji,
        monthlyBudgetMinor: row.monthlyBudgetMinor,
        tint: row.tint,
        sortOrder: row.sortOrder,
        system: row.system,
      }),
    ),
});

// --- Payment methods ---

export const pushPaymentMethods = mutationGeneric({
  args: {
    workspaceId: v.string(),
    operations: v.array(paymentMethodOperationValidator),
  },
  handler: async (ctx, { workspaceId, operations }) =>
    pushTypedBatch(ctx, workspaceId, operations, "paymentMethod", (op) => ({
      name: op.name,
      type: op.type,
      detail: op.detail,
      archived: op.archived,
    })),
});

export const pullPaymentMethods = queryGeneric({
  args: {
    workspaceId: v.string(),
    afterRevision: v.number(),
    limit: v.number(),
  },
  handler: async (ctx, args) =>
    pullTypedPage(
      ctx,
      "paymentMethods",
      args.workspaceId,
      args.afterRevision,
      args.limit,
      (row) => ({
        ...mapCommon(row),
        name: row.name,
        type: row.type,
        detail: row.detail,
        archived: row.archived,
      }),
    ),
});

// --- Transactions ---

export const pushTransactions = mutationGeneric({
  args: {
    workspaceId: v.string(),
    operations: v.array(transactionOperationValidator),
  },
  handler: async (ctx, { workspaceId, operations }) =>
    pushTypedBatch(
      ctx,
      workspaceId,
      operations,
      "transaction",
      (op) => ({
        name: op.name,
        amountMinor: op.amountMinor,
        occurredAt: op.occurredAt,
        categoryId: op.categoryId,
        paymentMethodId: op.paymentMethodId,
        ...(op.currency !== undefined ? { currency: op.currency } : {}),
        ...(op.sourceCurrency !== undefined
          ? { sourceCurrency: op.sourceCurrency }
          : {}),
        ...(op.sourceAmountMinor !== undefined
          ? { sourceAmountMinor: op.sourceAmountMinor }
          : {}),
        ...(op.exchangeRate !== undefined ? { exchangeRate: op.exchangeRate } : {}),
      }),
      { validate: (op) => assertAmountMinor(op.amountMinor) },
    ),
});

export const pullTransactions = queryGeneric({
  args: {
    workspaceId: v.string(),
    afterRevision: v.number(),
    limit: v.number(),
  },
  handler: async (ctx, args) =>
    pullTypedPage(
      ctx,
      "transactions",
      args.workspaceId,
      args.afterRevision,
      args.limit,
      (row) => ({
        ...mapCommon(row),
        name: row.name,
        amountMinor: row.amountMinor,
        occurredAt: row.occurredAt,
        categoryId: row.categoryId,
        paymentMethodId: row.paymentMethodId,
        currency: row.currency,
        sourceCurrency: row.sourceCurrency,
        sourceAmountMinor: row.sourceAmountMinor,
        exchangeRate: row.exchangeRate,
      }),
    ),
});

// --- Recurring ---

export const pushRecurring = mutationGeneric({
  args: {
    workspaceId: v.string(),
    operations: v.array(recurringOperationValidator),
  },
  handler: async (ctx, { workspaceId, operations }) =>
    pushTypedBatch(
      ctx,
      workspaceId,
      operations,
      "recurring",
      (op) => ({
        name: op.name,
        amountMinor: op.amountMinor,
        categoryId: op.categoryId,
        paymentMethodId: op.paymentMethodId,
        frequency: op.frequency,
        anchorDate: op.anchorDate,
        paused: op.paused,
        ...(op.currency !== undefined ? { currency: op.currency } : {}),
      }),
      {
        validate: (op) => {
          assertAmountMinor(op.amountMinor);
          assertAnchorDate(op.anchorDate);
        },
      },
    ),
});

export const pullRecurring = queryGeneric({
  args: {
    workspaceId: v.string(),
    afterRevision: v.number(),
    limit: v.number(),
  },
  handler: async (ctx, args) =>
    pullTypedPage(
      ctx,
      "recurring",
      args.workspaceId,
      args.afterRevision,
      args.limit,
      (row) => ({
        ...mapCommon(row),
        name: row.name,
        amountMinor: row.amountMinor,
        categoryId: row.categoryId,
        paymentMethodId: row.paymentMethodId,
        frequency: row.frequency,
        anchorDate: row.anchorDate,
        paused: row.paused,
        currency: row.currency,
      }),
    ),
});

// --- Lends ---

export const pushLends = mutationGeneric({
  args: {
    workspaceId: v.string(),
    operations: v.array(lendOperationValidator),
  },
  handler: async (ctx, { workspaceId, operations }) =>
    pushTypedBatch(
      ctx,
      workspaceId,
      operations,
      "lend",
      (op) => ({
        contactName: op.contactName,
        ...(op.contactId !== undefined ? { contactId: op.contactId } : {}),
        amountMinor: op.amountMinor,
        occurredAt: op.occurredAt,
        comment: op.comment,
        ...(op.kind !== undefined ? { kind: op.kind } : {}),
      }),
      { validate: (op) => assertAmountMinor(op.amountMinor) },
    ),
});

export const pullLends = queryGeneric({
  args: {
    workspaceId: v.string(),
    afterRevision: v.number(),
    limit: v.number(),
  },
  handler: async (ctx, args) =>
    pullTypedPage(
      ctx,
      "lends",
      args.workspaceId,
      args.afterRevision,
      args.limit,
      (row) => ({
        ...mapCommon(row),
        contactName: row.contactName,
        contactId: row.contactId,
        amountMinor: row.amountMinor,
        occurredAt: row.occurredAt,
        comment: row.comment,
        kind: row.kind,
      }),
    ),
});

// --- Email messages ---

export const pushEmailMessages = mutationGeneric({
  args: {
    workspaceId: v.string(),
    operations: v.array(emailMessageOperationValidator),
  },
  handler: async (ctx, { workspaceId, operations }) =>
    pushTypedBatch(ctx, workspaceId, operations, "emailMessage", (op) => ({
      accountId: op.accountId,
      accountEmail: op.accountEmail,
      gmailMessageId: op.gmailMessageId,
      threadId: op.threadId,
      rfcMessageId: op.rfcMessageId,
      senderName: op.senderName,
      senderAddress: op.senderAddress,
      subject: op.subject,
      snippet: op.snippet,
      internalDate: op.internalDate,
      normalizedBodyText: op.normalizedBodyText,
      analyzerType: op.analyzerType,
      modelVersion: op.modelVersion,
      promptVersion: op.promptVersion,
      classification: op.classification,
      merchant: op.merchant,
      amount: op.amount,
      currency: op.currency,
      occurredAt: op.occurredAt,
      categoryId: op.categoryId,
      paymentMethodId: op.paymentMethodId,
      paymentLastFour: op.paymentLastFour,
      reference: op.reference,
      state: op.state,
      linkedTransactionId: op.linkedTransactionId,
      analyzedAt: op.analyzedAt,
      reviewedAt: op.reviewedAt,
      createdAt: op.createdAt,
      updatedAt: op.updatedAt,
    })),
});

export const pullEmailMessages = queryGeneric({
  args: {
    workspaceId: v.string(),
    afterRevision: v.number(),
    limit: v.number(),
  },
  handler: async (ctx, args) =>
    pullTypedPage(
      ctx,
      "emailMessages",
      args.workspaceId,
      args.afterRevision,
      args.limit,
      (row) => ({
        ...mapCommon(row),
        accountId: row.accountId,
        accountEmail: row.accountEmail,
        gmailMessageId: row.gmailMessageId,
        threadId: row.threadId,
        rfcMessageId: row.rfcMessageId,
        senderName: row.senderName,
        senderAddress: row.senderAddress,
        subject: row.subject,
        snippet: row.snippet,
        internalDate: row.internalDate,
        normalizedBodyText: row.normalizedBodyText,
        analyzerType: row.analyzerType,
        modelVersion: row.modelVersion,
        promptVersion: row.promptVersion,
        classification: row.classification,
        merchant: row.merchant,
        amount: row.amount,
        currency: row.currency,
        occurredAt: row.occurredAt,
        categoryId: row.categoryId,
        paymentMethodId: row.paymentMethodId,
        paymentLastFour: row.paymentLastFour,
        reference: row.reference,
        state: row.state,
        linkedTransactionId: row.linkedTransactionId,
        analyzedAt: row.analyzedAt,
        reviewedAt: row.reviewedAt,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      }),
    ),
});

// --- Preferences ---

export const pushPreferences = mutationGeneric({
  args: {
    workspaceId: v.string(),
    operations: v.array(preferencesOperationValidator),
  },
  handler: async (ctx, { workspaceId, operations }) =>
    pushTypedBatch(
      ctx,
      workspaceId,
      operations,
      "preferences",
      (op) => ({
        profileName: op.profileName,
        profileEmail: op.profileEmail,
        currency: op.currency,
        weekStart: op.weekStart,
        ...(op.theme !== undefined ? { theme: op.theme } : {}),
        ...(op.navGlassOpacity !== undefined
          ? { navGlassOpacity: op.navGlassOpacity }
          : {}),
        defaultView: op.defaultView,
        ...(op.defaultStatsRange !== undefined
          ? { defaultStatsRange: op.defaultStatsRange }
          : {}),
        notifications: op.notifications,
        defaultPaymentMethodId: op.defaultPaymentMethodId,
      }),
      {
        validate: (op) => {
          if (op.entityId !== "preferences") throw new Error("Entity ID mismatch");
        },
      },
    ),
});

export const pullPreferences = queryGeneric({
  args: {
    workspaceId: v.string(),
    afterRevision: v.number(),
    limit: v.number(),
  },
  handler: async (ctx, args) =>
    pullTypedPage(
      ctx,
      "preferences",
      args.workspaceId,
      args.afterRevision,
      args.limit,
      (row) => ({
        ...mapCommon(row),
        profileName: row.profileName,
        profileEmail: row.profileEmail,
        currency: row.currency,
        weekStart: row.weekStart,
        theme: row.theme,
        navGlassOpacity: row.navGlassOpacity,
        defaultView: row.defaultView,
        defaultStatsRange: row.defaultStatsRange,
        notifications: row.notifications,
        defaultPaymentMethodId: row.defaultPaymentMethodId,
      }),
    ),
});

/**
 * Clear typed + blob rows for the given entity types (paged). Shared by web
 * Sync now / account wipe; old blob-only clear is replaced with dual clear.
 */
export const clearWorkspaceTyped = mutationGeneric({
  args: {
    workspaceId: v.string(),
    entityTypes: v.array(entityTypeValidator),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, { workspaceId, entityTypes, limit }) => {
    const identity = await requireIdentity(ctx);
    const ownerId = identity.tokenIdentifier;
    if (workspaceId !== "global") throw new Error("Unsupported workspace");
    const types = [...new Set(entityTypes)] as EntityTypeName[];
    if (types.length === 0) throw new Error("entityTypes must not be empty");
    const take = Math.max(1, Math.min(200, Math.floor(limit ?? 100)));

    let deleted = 0;
    let hasMore = false;
    for (const entityType of types) {
      const remaining = take - deleted;
      if (remaining <= 0) {
        hasMore = true;
        break;
      }
      const result = await clearEntityTypeBoth(
        ctx,
        ownerId,
        workspaceId,
        entityType,
        remaining,
      );
      deleted += result.deleted;
      if (!result.exhausted) {
        hasMore = true;
        break;
      }
    }

    if (!hasMore) {
      // Reset workspace revision only when every entity type is gone.
      const leftoverBlob = await ctx.db
        .query("entities")
        .withIndex("by_owner_and_workspace_and_revision", (q: any) =>
          q.eq("ownerId", ownerId).eq("workspaceId", workspaceId),
        )
        .first();
      if (!leftoverBlob) {
        const workspace = await loadWorkspace(ctx, ownerId, workspaceId);
        if (workspace && workspace.revision !== 0) {
          await ctx.db.patch(workspace._id, { revision: 0 });
        }
      }
    }
    return { deleted, hasMore };
  },
});
