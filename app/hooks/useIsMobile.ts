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
      const timer = window.setTimeout(() => setIsMobile(true), 0);
      return () => window.clearTimeout(timer);
    }

    if (isElectronApp()) {
      const timer = window.setTimeout(() => setIsMobile(false), 0);
      return () => window.clearTimeout(timer);
    }

    const query = window.matchMedia(`(max-width: ${breakpoint - 1}px)`);
    const update = () => setIsMobile(query.matches);
    const timer = window.setTimeout(update, 0);
    query.addEventListener("change", update);
    return () => { window.clearTimeout(timer); query.removeEventListener("change", update); };
  }, [breakpoint]);

  return isMobile;
}
