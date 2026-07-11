"use client";

import { useEffect, useMemo, useState } from "react";
import type { ID } from "@/lib/types";

/** Selection mode for bulk actions on the Activity list. */
export function useActivitySelection(visibleIds: ID[]) {
  const [selecting, setSelecting] = useState(false);
  const [selected, setSelected] = useState<Set<ID>>(() => new Set());
  const visibleKey = useMemo(() => visibleIds.join("\0"), [visibleIds]);

  useEffect(() => {
    if (!selecting) return;
    const ids = visibleKey ? visibleKey.split("\0") : [];
    const visible = new Set(ids);
    setSelected((prev) => {
      let changed = false;
      const next = new Set<ID>();
      for (const id of prev) {
        if (visible.has(id)) next.add(id);
        else changed = true;
      }
      return changed ? next : prev;
    });
  }, [visibleKey, selecting]);

  const selectedCount = selected.size;
  const allSelected =
    visibleIds.length > 0 && visibleIds.every((id) => selected.has(id));

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
    selected,
    selectedCount,
    allSelected,
    enter,
    exit,
    toggle,
    selectAll,
    deselectAll,
    selectedIds: [...selected],
  };
}
