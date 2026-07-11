import { deleteAllLocalDatabases } from "@/data/db";
import { stopSync } from "@/sync/coordinator";

/** Stop sync, wipe IndexedDB, then end the AuthKit session. */
export async function signOutAndClearLocal(
  signOut: (options?: { returnTo?: string }) => Promise<void> | void,
) {
  stopSync();
  await deleteAllLocalDatabases();
  await signOut({ returnTo: window.location.origin });
}
