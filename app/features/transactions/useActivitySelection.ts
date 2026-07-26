"use client";

import { useCallback, useMemo, useState } from "react";
import type { ID } from "@/lib/types";

/**
 * Selection mode for bulk actions on the Activity list. Every callback is stable so
 * memoised rows are not invalidated by an unrelated parent render.
 */
export function useActivitySelection(visibleIds: ID[]) {
  const [selecting, setSelecting] = useState(false);
  const [selected, setSelected] = useState<Set<ID>>(() => new Set());

  const visibleSelected = useMemo(() => {
    const visible = new Set(visibleIds);
    return new Set([...selected].filter((id) => visible.has(id)));
  }, [selected, visibleIds]);

  const selectedCount = visibleSelected.size;
  const allSelected =
    visibleIds.length > 0 && visibleIds.every((id) => visibleSelected.has(id));

  const enter = useCallback(() => setSelecting(true), []);
  const exit = useCallback(() => {
    setSelecting(false);
    setSelected(new Set());
  }, []);
  const toggle = useCallback((id: ID) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);
  // Depends on the visible set, so identity changes with the list — only the
  // per-row `toggle` needs to stay stable for memoised rows.
  const selectAll = () => setSelected(new Set(visibleIds));
  const deselectAll = useCallback(() => setSelected(new Set()), []);

  return {
    selecting,
    selected: visibleSelected,
    selectedCount,
    allSelected,
    enter,
    exit,
    toggle,
    selectAll,
    deselectAll,
    selectedIds: [...visibleSelected],
  };
}
