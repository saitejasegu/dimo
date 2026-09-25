import type { ConvexReactClient } from "convex/react";
import { deleteAllLocalDatabases } from "@/data/db";
import { clearCloudWorkspace, stopSync } from "@/sync/coordinator";
import { clearCachedUser } from "@/auth/cachedUser";

type SignOut = (options?: { returnTo?: string }) => Promise<void> | void;

/** Stop sync, wipe IndexedDB, then end the AuthKit session. */
export async function signOutAndClearLocal(signOut: SignOut) {
  stopSync();
  clearCachedUser();
  await deleteAllLocalDatabases();
  await signOut({ returnTo: window.location.origin });
}

/**
 * Wipe cloud workspace data, wipe IndexedDB, then sign out.
 * Requires network so Convex data is not left behind.
 */
export async function deleteAccountAndSignOut(
  client: ConvexReactClient,
  signOut: SignOut,
) {
  if (!navigator.onLine) {
    throw new Error("Connect to the internet to delete your account data.");
  }
  stopSync();
  await clearCloudWorkspace(client);
  clearCachedUser();
  await deleteAllLocalDatabases();
  await signOut({ returnTo: window.location.origin });
}
