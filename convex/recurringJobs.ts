import { internalMutationGeneric } from "convex/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";
import { writeTyped } from "./compat";
import { convertMinorAmount, rateOn } from "./exchangeRates";

/* eslint-disable @typescript-eslint/no-explicit-any */

const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;
const PAGE_SIZE = 25;
const JOB_DEVICE_ID = "convex-recurring-job";

type Frequency = "monthly" | "yearly";
type RecurringRow = {
  ownerId?: string;
  workspaceId: string;
  entityId: string;
  deleted: boolean;
  name: string;
  amountMinor: number;
  categoryId: string;
  paymentMethodId: string | null;
  frequency: Frequency;
  anchorDate: string;
  paused: boolean;
  currency?: string;
};

type DefaultCurrency = "INR" | "USD" | "EUR";

/** Read an owner's default currency from the typed preferences table. */
async function ownerDefaultCurrency(
  ctx: { db: any },
  ownerId: string,
  workspaceId: string,
): Promise<DefaultCurrency> {
  const prefs = await ctx.db
    .query("preferences")
    .withIndex("by_owner_workspace_entity", (q: any) =>
      q
        .eq("ownerId", ownerId)
        .eq("workspaceId", workspaceId)
        .eq("entityId", "preferences"),
    )
    .unique();
  if (prefs && !prefs.deleted) {
    const currency = prefs.currency;
    return currency === "USD" || currency === "EUR" ? currency : "INR";
  }
  return "INR";
}

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
  recurring: Pick<RecurringRow, "anchorDate" | "frequency">,
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
      .query("recurring")
      .paginate({ cursor: args.cursor ?? null, numItems: PAGE_SIZE });

    // One preferences read per owner per page keeps the default-currency lookup cheap.
    const currencyCache = new Map<string, DefaultCurrency>();
    const defaultCurrencyFor = async (ownerId: string, workspaceId: string) => {
      const cached = currencyCache.get(ownerId);
      if (cached) return cached;
      const resolved = await ownerDefaultCurrency(ctx, ownerId, workspaceId);
      currencyCache.set(ownerId, resolved);
      return resolved;
    };

    let created = 0;
    for (const row of page.page as RecurringRow[]) {
      if (row.deleted || !row.ownerId || row.workspaceId !== "global") continue;
      if (row.paused || !isRecurringDueOn(row, dateKey)) continue;

      const entityId = recurringTransactionId(row.entityId, dateKey);
      const existing = await ctx.db
        .query("transactions")
        .withIndex("by_owner_workspace_entity", (q: any) =>
          q
            .eq("ownerId", row.ownerId)
            .eq("workspaceId", row.workspaceId)
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

      // Convert foreign-currency bills into the owner's default currency at that
      // day's rate. Absent/matching currency keeps the legacy straight copy.
      const defaultCurrency = await defaultCurrencyFor(row.ownerId, row.workspaceId);
      let amountMinor = row.amountMinor;
      let source: {
        sourceCurrency: string;
        sourceAmountMinor: number;
        exchangeRate: number;
      } | null = null;
      if (row.currency && row.currency !== "") {
        if (row.currency !== defaultCurrency) {
          const ratio = await rateOn(ctx, dateKey, row.currency, defaultCurrency);
          if (ratio != null) {
            amountMinor = convertMinorAmount(
              row.amountMinor,
              row.currency,
              defaultCurrency,
              ratio,
            );
            source = {
              sourceCurrency: row.currency,
              sourceAmountMinor: row.amountMinor,
              exchangeRate: ratio,
            };
          } else {
            // Never label a foreign amount as the owner's default currency.
            // Leaving the occurrence absent allows a same-date retry after the
            // rates refresh succeeds.
            console.warn(
              `materializeDue: no rate ${row.currency}->${defaultCurrency} on ${dateKey}; skipping occurrence`,
            );
            continue;
          }
        }
      }

      await writeTyped(ctx, "transaction", {
        ownerId: row.ownerId,
        workspaceId: row.workspaceId,
        entityId,
        version: {
          timestamp: Date.now(),
          counter: 0,
          deviceId: JOB_DEVICE_ID,
        },
        deleted: false,
        revision,
        name: row.name,
        amountMinor,
        occurredAt,
        categoryId: row.categoryId,
        paymentMethodId: row.paymentMethodId,
        currency: defaultCurrency,
        ...(source ?? {}),
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
