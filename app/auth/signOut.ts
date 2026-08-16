import type { ConvexReactClient } from "convex/react";
import { deleteAllLocalDatabases } from "@/data/db";
import { clearCachedRates } from "@/features/currency/rates";
import { clearCloudWorkspace, stopSync } from "@/sync/coordinator";

type SignOut = (options?: { returnTo?: string }) => Promise<void> | void;

/** Stop sync, wipe IndexedDB, then end the AuthKit session. */
export async function signOutAndClearLocal(signOut: SignOut) {
  stopSync();
  await deleteAllLocalDatabases();
  clearCachedRates();
  await signOut({ returnTo: window.location.origin });
}

/**
 * Wipe cloud workspace data, wipe IndexedDB, then sign out.
 * Requires network so Convex data is not left behind.
 * Note: this clears Dimo cloud + local data; the WorkOS identity itself is
 * not deleted (requires a server-side WorkOS Admin API call).
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
  await deleteAllLocalDatabases();
  clearCachedRates();
  await signOut({ returnTo: window.location.origin });
}
