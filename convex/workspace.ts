/**
 * Per-owner workspace helpers shared by typed sync and lending collaboration.
 */
/* eslint-disable @typescript-eslint/no-explicit-any */

export type AuthIdentity = {
  tokenIdentifier: string;
  name?: string;
  email?: string;
};

export async function requireIdentity(ctx: {
  auth: { getUserIdentity(): Promise<AuthIdentity | null> };
}) {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) throw new Error("Not authenticated");
  return identity;
}

export function profileFromPreferences(fields: Record<string, unknown>) {
  const name = typeof fields.profileName === "string" ? fields.profileName.trim() : "";
  const email = typeof fields.profileEmail === "string" ? fields.profileEmail.trim() : "";
  return {
    ...(name ? { name } : {}),
    ...(email ? { email } : {}),
  };
}

export function profileFromIdentity(identity: AuthIdentity) {
  const name = identity.name?.trim() ?? "";
  const email = identity.email?.trim() ?? "";
  return {
    ...(name ? { name } : {}),
    ...(email ? { email } : {}),
  };
}

export async function loadWorkspace(ctx: { db: any }, ownerId: string, workspaceId: string) {
  return await ctx.db
    .query("workspaces")
    .withIndex("by_owner_and_workspace", (q: any) =>
      q.eq("ownerId", ownerId).eq("workspaceId", workspaceId),
    )
    .unique();
}

export async function persistWorkspace(
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
