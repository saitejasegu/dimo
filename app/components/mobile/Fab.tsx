"use client";

import type { OverlayKey, ViewKey } from "@/lib/types";
import { useAppActions, useAppState } from "@/store/app-store";
import { PlusIcon } from "@/components/ui/icons";

const FAB_BY_VIEW: Partial<
  Record<ViewKey, { overlay: Exclude<OverlayKey, null>; label: string }>
> = {
  home: { overlay: "add", label: "Add expense" },
  tx: { overlay: "add", label: "Add expense" },
  budgets: { overlay: "category", label: "New category" },
};

/** Floating add button for screens that create records. */
export function Fab() {
  const { view } = useAppState();
  const { openOverlay } = useAppActions();
  const action = FAB_BY_VIEW[view];
  if (!action) return null;

  return (
    <button
      type="button"
      onClick={() => openOverlay(action.overlay)}
      aria-label={action.label}
      className="absolute bottom-[calc(5.75rem+env(safe-area-inset-bottom,0px))] right-5 z-[15] flex h-[54px] w-[54px] items-center justify-center rounded-[18px] !bg-green !text-white shadow-[0_12px_28px_-8px_rgba(31,157,99,0.6)]"
    >
      <PlusIcon />
    </button>
  );
}
