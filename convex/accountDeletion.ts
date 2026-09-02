"use node";

import { actionGeneric } from "convex/server";
import { v } from "convex/values";
import { workosUserIdFromIdentity } from "./accountDeletionLib";

type AuthIdentity = {
  tokenIdentifier: string;
  subject?: string;
};

async function requireIdentity(ctx: {
  auth: { getUserIdentity(): Promise<AuthIdentity | null> };
}) {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) throw new Error("Not authenticated");
  return identity;
}

/**
 * Deletes the authenticated WorkOS user after cloud workspace wipe.
 * Requires Convex deploy env `WORKOS_API_KEY`. When unset, returns
 * `identityDeleted: false` so clients can still clear Dimo data and sign out.
 */
export const deleteWorkOSUser = actionGeneric({
  args: {},
  returns: v.object({
    identityDeleted: v.boolean(),
    reason: v.union(v.string(), v.null()),
  }),
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const apiKey = process.env.WORKOS_API_KEY?.trim() ?? "";
    if (!apiKey) {
      return {
        identityDeleted: false,
        reason:
          "WORKOS_API_KEY is not configured on the Convex deployment; Dimo data was cleared but the login identity remains.",
      };
    }

    const userId = workosUserIdFromIdentity(identity);
    const response = await fetch(
      `https://api.workos.com/user_management/users/${encodeURIComponent(userId)}`,
      {
        method: "DELETE",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          Accept: "application/json",
        },
      },
    );

    // 404: already gone — treat as success for idempotent account deletion.
    if (response.ok || response.status === 404) {
      return { identityDeleted: true, reason: null };
    }

    const bodyText = (await response.text()).trim().slice(0, 300);
    throw new Error(
      bodyText
        ? `WorkOS identity deletion failed (HTTP ${response.status}): ${bodyText}`
        : `WorkOS identity deletion failed (HTTP ${response.status}).`,
    );
  },
});
