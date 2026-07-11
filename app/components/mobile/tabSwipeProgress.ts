"use client";

import { useSyncExternalStore } from "react";

type Snapshot = {
  /** Fractional tab index aligned with the pager (0 = first tab). */
  progress: number;
  /** True while the finger is actively dragging the pager. */
  interactive: boolean;
};

let snapshot: Snapshot = { progress: 0, interactive: false };
const listeners = new Set<() => void>();

function emit() {
  for (const listener of listeners) listener();
}

export function setTabSwipeProgress(progress: number, interactive = false) {
  if (snapshot.progress === progress && snapshot.interactive === interactive) {
    return;
  }
  snapshot = { progress, interactive };
  emit();
}

export function getTabSwipeProgress() {
  return snapshot;
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

/** Subscribe to pager swipe progress without re-rendering unrelated trees. */
export function useTabSwipeProgress() {
  return useSyncExternalStore(subscribe, getTabSwipeProgress, getTabSwipeProgress);
}
