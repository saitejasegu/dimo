import type { ConvexReactClient } from "convex/react";
import { makeFunctionReference } from "convex/server";
import { deleteAllLocalDatabases } from "@/data/db";
import { clearCachedRates } from "@/features/currency/rates";
import { clearCloudWorkspace, stopSync } from "@/sync/coordinator";

type SignOut = (options?: { returnTo?: string }) => Promise<void> | void;

type DeleteIdentityResult = {
  identityDeleted: boolean;
  reason: string | null;
};

const deleteWorkOSUser = makeFunctionReference<
  "action",
  Record<string, never>,
  DeleteIdentityResult
>("accountDeletion:deleteWorkOSUser");

/** Stop sync, wipe IndexedDB, then end the AuthKit session. */
export async function signOutAndClearLocal(signOut: SignOut) {
  stopSync();
  await deleteAllLocalDatabases();
  clearCachedRates();
  await signOut({ returnTo: window.location.origin });
}

/**
 * Wipe cloud workspace data, attempt WorkOS identity deletion, wipe IndexedDB,
 * then sign out. Requires network so Convex data is not left behind.
 */
export async function deleteAccountAndSignOut(
  client: ConvexReactClient,
  signOut: SignOut,
): Promise<DeleteIdentityResult> {
  if (!navigator.onLine) {
    throw new Error("Connect to the internet to delete your account data.");
  }
  stopSync();
  await clearCloudWorkspace(client);
  const identityResult = await client.action(deleteWorkOSUser, {});
  await deleteAllLocalDatabases();
  clearCachedRates();
  await signOut({ returnTo: window.location.origin });
  return identityResult;
}
