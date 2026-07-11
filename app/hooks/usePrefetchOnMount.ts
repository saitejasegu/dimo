"use client";

import { useEffect } from "react";

/** Kick off dynamic imports after the first paint so navigation/overlays are warm. */
export function usePrefetchOnMount(loaders: ReadonlyArray<() => Promise<unknown>>) {
  useEffect(() => {
    for (const load of loaders) void load();
  }, [loaders]);
}
