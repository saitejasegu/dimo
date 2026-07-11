"use client";

import { useCallback, useSyncExternalStore } from "react";
import { isElectronApp, isNativeApp } from "@/lib/native";

function readIsMobile(breakpoint: number): boolean {
  if (isNativeApp()) return true;
  if (isElectronApp()) return false;
  return window.matchMedia(`(max-width: ${breakpoint - 1}px)`).matches;
}

/**
 * Tracks whether the viewport is below the given breakpoint.
 * Resolves synchronously on the client so the shell can paint immediately.
 * Capacitor always uses the mobile shell; Electron always uses the web UI.
 */
export function useIsMobile(breakpoint = 900): boolean {
  const subscribe = useCallback(
    (onStoreChange: () => void) => {
      if (isNativeApp() || isElectronApp()) return () => {};
      const query = window.matchMedia(`(max-width: ${breakpoint - 1}px)`);
      query.addEventListener("change", onStoreChange);
      return () => query.removeEventListener("change", onStoreChange);
    },
    [breakpoint],
  );

  const getSnapshot = useCallback(() => readIsMobile(breakpoint), [breakpoint]);

  return useSyncExternalStore(subscribe, getSnapshot, () => false);
}
