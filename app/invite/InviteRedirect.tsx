"use client";

import { useEffect } from "react";
import { normalizeInviteCode, PENDING_INVITE_STORAGE_KEY } from "@/store/lending-sharing";

/**
 * `/invite?code=…` links. The static export cannot route into app state, so the
 * code is parked in session storage (it survives the sign-in redirect) and the
 * app opens the join dialog once signed in.
 */
export function InviteRedirect() {
  useEffect(() => {
    const code = normalizeInviteCode(new URLSearchParams(window.location.search).get("code") ?? "");
    if (code) {
      try {
        sessionStorage.setItem(PENDING_INVITE_STORAGE_KEY, code);
      } catch {
        // Private browsing without storage: the user can still enter the code.
      }
    }
    window.location.replace("/");
  }, []);

  return <p className="text-sm text-muted">Opening your invite…</p>;
}
