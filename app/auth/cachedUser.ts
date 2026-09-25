import type { AppUser } from "@/store/app-store";

/**
 * The last signed-in identity, so a returning session can open its local database and
 * paint before WorkOS and Convex finish re-authenticating over the network. Holds only
 * what AuthKit already exposes to the page; cleared on sign-out.
 */
const STORAGE_KEY = "dimo:last-user";

let cachedRaw: string | null | undefined;
let cachedUser: AppUser | null = null;

function parse(raw: string | null): AppUser | null {
  if (!raw) return null;
  try {
    const value = JSON.parse(raw) as Partial<AppUser>;
    if (typeof value.id !== "string" || !value.id) return null;
    return {
      id: value.id,
      name: typeof value.name === "string" ? value.name : "",
      email: typeof value.email === "string" ? value.email : "",
      photoUrl: typeof value.photoUrl === "string" ? value.photoUrl : null,
    };
  } catch {
    return null;
  }
}

/** Stable snapshot for `useSyncExternalStore`: same object until the stored value changes. */
export function readCachedUser(): AppUser | null {
  let raw: string | null = null;
  try {
    raw = window.localStorage.getItem(STORAGE_KEY);
  } catch {
    return null;
  }
  if (raw !== cachedRaw) {
    cachedRaw = raw;
    cachedUser = parse(raw);
  }
  return cachedUser;
}

export function writeCachedUser(user: AppUser) {
  try {
    const raw = JSON.stringify(user);
    if (raw !== window.localStorage.getItem(STORAGE_KEY)) {
      window.localStorage.setItem(STORAGE_KEY, raw);
    }
  } catch {
    // Storage unavailable (private mode quota) — cold start just waits for auth.
  }
}

export function clearCachedUser() {
  try {
    window.localStorage.removeItem(STORAGE_KEY);
  } catch {
    // Nothing to clear.
  }
}
