"use client";

import { useEffect, useRef, useState } from "react";

const POLL_MS = 60_000;

interface VersionPayload {
  version?: string;
}

async function fetchVersion(): Promise<string | null> {
  try {
    const response = await fetch(`/version.json?t=${Date.now()}`, {
      cache: "no-store",
    });
    if (!response.ok) return null;
    const data = (await response.json()) as VersionPayload;
    return typeof data.version === "string" && data.version.length > 0
      ? data.version
      : null;
  } catch {
    return null;
  }
}

/** Detects a newer Vercel deploy by polling `/version.json`. */
export function useAppUpdate() {
  const [updateAvailable, setUpdateAvailable] = useState(false);
  const currentVersion = useRef<string | null>(null);

  useEffect(() => {
    if (process.env.NODE_ENV === "development") return;
    if (typeof window === "undefined") return;
    if (!/^https?:$/.test(window.location.protocol)) return;

    let cancelled = false;

    async function check() {
      if (cancelled || document.visibilityState === "hidden") return;
      const next = await fetchVersion();
      if (cancelled || !next) return;

      if (!currentVersion.current) {
        currentVersion.current = next;
        return;
      }

      if (next !== currentVersion.current) {
        setUpdateAvailable(true);
      }
    }

    void check();
    const id = window.setInterval(() => {
      void check();
    }, POLL_MS);

    const onVisible = () => {
      if (document.visibilityState === "visible") void check();
    };
    document.addEventListener("visibilitychange", onVisible);

    return () => {
      cancelled = true;
      window.clearInterval(id);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, []);

  function refresh() {
    window.location.reload();
  }

  return { updateAvailable, refresh };
}
