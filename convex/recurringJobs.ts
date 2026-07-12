import { internalMutationGeneric } from "convex/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";

/* Generic Convex functions intentionally use untyped index builders until a
   deployment is linked and Convex generates its schema-specific bindings. */
/* eslint-disable @typescript-eslint/no-explicit-any */

const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;
const PAGE_SIZE = 25;
const JOB_DEVICE_ID = "convex-recurring-job";

type Frequency = "monthly" | "yearly";
type RecurringPayload = {
  id: string;
  name: string;
  amountMinor: number;
  categoryId: string;
  paymentMethodId: string | null;
  frequency: Frequency;
  anchorDate: string;
  paused: boolean;
};

type DateParts = { year: number; month: number; day: number };

function parseDateKey(value: string): DateParts | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    return null;
  }
  return { year, month, day };
}

function daysInMonth(year: number, month: number) {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

export function istDateKey(now = Date.now()) {
  const ist = new Date(now + IST_OFFSET_MS);
  const year = ist.getUTCFullYear();
  const month = String(ist.getUTCMonth() + 1).padStart(2, "0");
  const day = String(ist.getUTCDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

/** Compare calendar dates only. Both the cron date and occurrence use IST. */
export function isRecurringDueOn(
  recurring: Pick<RecurringPayload, "anchorDate" | "frequency">,
  dateKey: string,
) {
  const anchor = parseDateKey(recurring.anchorDate);
  const target = parseDateKey(dateKey);
  if (!anchor || !target || recurring.anchorDate > dateKey) return false;

  const dueDay = Math.min(anchor.day, daysInMonth(target.year, target.month));
  if (target.day !== dueDay) return false;

  if (recurring.frequency === "monthly") {
    return (
      target.year > anchor.year ||
      (target.year === anchor.year && target.month >= anchor.month)
    );
  }

  return target.year >= anchor.year && target.month === anchor.month;
}

/** Noon IST keeps the transaction on the intended calendar date on clients. */
export function occurrenceTimestampIST(dateKey: string) {
  const date = parseDateKey(dateKey);
  if (!date) throw new Error("Invalid IST date key");
  return Date.UTC(date.year, date.month - 1, date.day, 6, 30, 0, 0);
}

export function recurringTransactionId(recurringId: string, dateKey: string) {
  return `recurring:${recurringId}:${dateKey}`;
}

export const materializeDue = internalMutationGeneric({
  args: {
    dateKey: v.optional(v.string()),
    cursor: v.optional(v.union(v.string(), v.null())),
  },
  handler: async (ctx, args) => {
    const dateKey = args.dateKey ?? istDateKey();
    if (!parseDateKey(dateKey)) throw new Error("Invalid IST date key");

    const page = await ctx.db
      .query("entities")
      .withIndex("by_entity_type", (q: any) => q.eq("entityType", "recurring"))
      .paginate({ cursor: args.cursor ?? null, numItems: PAGE_SIZE });

    let created = 0;
    for (const row of page.page) {
      if (row.deleted || !row.ownerId || row.workspaceId !== "global") continue;
      const recurring = row.payload as RecurringPayload;
      if (recurring.paused || !isRecurringDueOn(recurring, dateKey)) continue;

      const entityId = recurringTransactionId(recurring.id, dateKey);
      const existing = await ctx.db
        .query("entities")
        .withIndex("by_owner_and_workspace_and_entity", (q: any) =>
          q
            .eq("ownerId", row.ownerId)
            .eq("workspaceId", row.workspaceId)
            .eq("entityType", "transaction")
            .eq("entityId", entityId),
        )
        .unique();
      // A transaction or its tombstone means this occurrence was already handled.
      if (existing) continue;

      let workspace = await ctx.db
        .query("workspaces")
        .withIndex("by_owner_and_workspace", (q: any) =>
          q.eq("ownerId", row.ownerId).eq("workspaceId", row.workspaceId),
        )
        .unique();
      const revision = (workspace?.revision ?? 0) + 1;
      const occurredAt = occurrenceTimestampIST(dateKey);
      const payload = {
        id: entityId,
        name: recurring.name,
        amountMinor: recurring.amountMinor,
        occurredAt,
        categoryId: recurring.categoryId,
        paymentMethodId: recurring.paymentMethodId,
      };
      await ctx.db.insert("entities", {
        ownerId: row.ownerId,
        workspaceId: row.workspaceId,
        entityType: "transaction",
        entityId,
        version: {
          timestamp: Date.now(),
          counter: 0,
          deviceId: JOB_DEVICE_ID,
        },
        payload,
        deleted: false,
        revision,
      });
      if (workspace) {
        await ctx.db.patch(workspace._id, { revision });
      } else {
        const workspaceId = await ctx.db.insert("workspaces", {
          ownerId: row.ownerId,
          workspaceId: row.workspaceId,
          revision,
        });
        workspace = await ctx.db.get(workspaceId);
      }
      created += 1;
    }

    if (!page.isDone) {
      await ctx.scheduler.runAfter(0, internal.recurringJobs.materializeDue, {
        dateKey,
        cursor: page.continueCursor,
      });
    }

    return { created, hasMore: !page.isDone, dateKey };
  },
});
