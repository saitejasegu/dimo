/**
 * Reads the caller's verified sign-in email from WorkOS so other people can
 * find this account to share a lending ledger. The address never comes from
 * the client: workspace and preference emails are client-settable and would
 * let anyone pose as someone else.
 */
import { makeFunctionReference } from "convex/server";
import { v } from "convex/values";
import { action } from "./_generated/server";

const storeVerifiedEmailRef = makeFunctionReference<"mutation">(
  "lending:storeVerifiedEmail",
);

const WORKOS_API_BASE = "https://api.workos.com";

type WorkOSUser = { email?: unknown; email_verified?: unknown };

export const refreshVerifiedEmail = action({
  args: {},
  returns: v.object({
    /** False when the deployment has no WorkOS API key configured. */
    available: v.boolean(),
    email: v.union(v.string(), v.null()),
  }),
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new Error("Not authenticated");
    const apiKey = process.env.WORKOS_API_KEY?.trim() ?? "";
    if (!apiKey) return { available: false, email: null };

    const response = await fetch(
      `${WORKOS_API_BASE}/user_management/users/${encodeURIComponent(identity.subject)}`,
      { headers: { Authorization: `Bearer ${apiKey}` } },
    );
    if (!response.ok) {
      throw new Error(`WorkOS user lookup failed (${response.status})`);
    }
    const user = (await response.json()) as WorkOSUser;
    if (typeof user.email !== "string" || user.email_verified !== true) {
      return { available: true, email: null };
    }
    await ctx.runMutation(storeVerifiedEmailRef, {
      ownerId: identity.tokenIdentifier,
      email: user.email,
    });
    return { available: true, email: user.email.trim().toLowerCase() };
  },
});
