/**
 * One-off backfill of profile photos from WorkOS, so people show up with their
 * photo before they next sign in. Run per deployment:
 *   npx convex run profilePhotos:backfillProfilePhotos
 * Each WorkOS environment has its own API key, so a deployment only sees the
 * users of the environment its `WORKOS_API_KEY` belongs to.
 */
import { makeFunctionReference } from "convex/server";
import { v } from "convex/values";
import { internalAction, internalMutation, internalQuery } from "./_generated/server";
import { isAllowedPhotoUrl } from "./lending";

const PAGE_SIZE = 50;
const WORKOS_API_BASE = "https://api.workos.com";

const pageRef = makeFunctionReference<
  "query",
  { cursor: string | null },
  { owners: Array<{ workspaceId: string; subject: string }>; cursor: string; isDone: boolean }
>("profilePhotos:workspacesWithoutPhoto");
const storeRef = makeFunctionReference<"mutation", { workspaceId: string; photoUrl: string }, boolean>(
  "profilePhotos:storeProfilePhoto",
);
const backfillRef = makeFunctionReference<"action", { cursor: string | null }>(
  "profilePhotos:backfillProfilePhotos",
);

/** A page of account workspaces that have no photo yet, with their WorkOS user id. */
export const workspacesWithoutPhoto = internalQuery({
  args: { cursor: v.union(v.string(), v.null()) },
  returns: v.object({
    owners: v.array(v.object({ workspaceId: v.id("workspaces"), subject: v.string() })),
    cursor: v.string(),
    isDone: v.boolean(),
  }),
  handler: async (ctx, { cursor }) => {
    const page = await ctx.db.query("workspaces").paginate({ numItems: PAGE_SIZE, cursor });
    const owners = page.page.flatMap((workspace) => {
      // Token identifiers look like `<issuer>|<WorkOS user id>`.
      const subject = workspace.ownerId?.split("|").pop();
      return workspace.workspaceId === "global" && !workspace.photoUrl && subject
        ? [{ workspaceId: workspace._id, subject }]
        : [];
    });
    return { owners, cursor: page.continueCursor, isDone: page.isDone };
  },
});

export const storeProfilePhoto = internalMutation({
  args: { workspaceId: v.id("workspaces"), photoUrl: v.string() },
  returns: v.boolean(),
  handler: async (ctx, { workspaceId, photoUrl }) => {
    const workspace = await ctx.db.get(workspaceId);
    if (!workspace || workspace.photoUrl || !isAllowedPhotoUrl(photoUrl)) return false;
    await ctx.db.patch(workspaceId, { photoUrl });
    return true;
  },
});

/** Fills missing photos one page at a time, scheduling the next page. */
export const backfillProfilePhotos = internalAction({
  args: { cursor: v.optional(v.union(v.string(), v.null())) },
  returns: v.object({ checked: v.number(), updated: v.number(), done: v.boolean() }),
  handler: async (ctx, args) => {
    const apiKey = process.env.WORKOS_API_KEY?.trim();
    if (!apiKey) throw new Error("WORKOS_API_KEY is not set on this deployment");
    const page = await ctx.runQuery(pageRef, { cursor: args.cursor ?? null });
    let updated = 0;
    for (const owner of page.owners) {
      const response = await fetch(
        `${WORKOS_API_BASE}/user_management/users/${encodeURIComponent(owner.subject)}`,
        { headers: { Authorization: `Bearer ${apiKey}` } },
      );
      // Users from another WorkOS environment aren't visible to this key.
      if (!response.ok) continue;
      const user = (await response.json()) as { profile_picture_url?: unknown };
      if (typeof user.profile_picture_url !== "string" || !user.profile_picture_url) continue;
      const stored = await ctx.runMutation(storeRef, {
        workspaceId: owner.workspaceId,
        photoUrl: user.profile_picture_url,
      });
      if (stored) updated += 1;
    }
    if (!page.isDone) await ctx.scheduler.runAfter(0, backfillRef, { cursor: page.cursor });
    return { checked: page.owners.length, updated, done: page.isDone };
  },
});
