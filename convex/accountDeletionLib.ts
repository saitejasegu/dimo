/** Pure helpers for WorkOS account deletion (safe to import from tests). */

type AuthIdentity = {
  tokenIdentifier: string;
  subject?: string;
};

/** WorkOS user id from JWT `tokenIdentifier` (`issuer|user_…`) or `subject`. */
export function workosUserIdFromIdentity(identity: AuthIdentity): string {
  const parts = identity.tokenIdentifier.split("|");
  if (parts.length >= 2) {
    const id = parts[parts.length - 1]?.trim() ?? "";
    if (id) return id;
  }
  const subject = identity.subject?.trim() ?? "";
  if (subject) return subject;
  throw new Error("Could not resolve WorkOS user id from identity.");
}
