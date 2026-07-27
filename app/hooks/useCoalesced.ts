"use client";

import { useEffect, useRef, useState } from "react";

/**
 * Trailing-edge coalescing for a rapidly changing value.
 *
 * A full initial sync commits one IndexedDB transaction per pulled page, and each one
 * re-emits the live query. Without this, every page would drive its own projection and
 * full re-render. One frame of delay folds a burst into a single update; the first
 * value is passed through immediately so first paint is not held back.
 */
export function useCoalesced<T>(value: T, delayMs = 16): T {
  const [settled, setSettled] = useState(value);
  const seenRef = useRef(false);

  useEffect(() => {
    if (!seenRef.current) {
      seenRef.current = true;
      setSettled(value);
      return;
    }
    const timer = setTimeout(() => setSettled(value), delayMs);
    return () => clearTimeout(timer);
  }, [value, delayMs]);

  return settled;
}
