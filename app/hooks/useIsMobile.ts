"use client";

import { useEffect, useState } from "react";
import { isElectronApp, isNativeApp } from "@/lib/native";

/**
 * Tracks whether the viewport is below the given breakpoint.
 * Returns `null` until mounted to avoid a hydration mismatch.
 * Capacitor always uses the mobile shell; Electron always uses the web UI.
 */
export function useIsMobile(breakpoint = 900): boolean | null {
  const [isMobile, setIsMobile] = useState<boolean | null>(null);

  useEffect(() => {
    if (isNativeApp()) {
      setIsMobile(true);
      return;
    }

    if (isElectronApp()) {
      setIsMobile(false);
      return;
    }

    const query = window.matchMedia(`(max-width: ${breakpoint - 1}px)`);
    const update = () => setIsMobile(query.matches);
    update();
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, [breakpoint]);

  return isMobile;
}
