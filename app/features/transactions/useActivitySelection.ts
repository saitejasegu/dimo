"use client";

import { useMemo, useState } from "react";
import type { ID } from "@/lib/types";

/** Selection mode for bulk actions on the Activity list. */
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

  const enter = () => setSelecting(true);
  const exit = () => {
    setSelecting(false);
    setSelected(new Set());
  };
  const toggle = (id: ID) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };
  const selectAll = () => setSelected(new Set(visibleIds));
  const deselectAll = () => setSelected(new Set());

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
