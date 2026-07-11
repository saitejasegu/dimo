"use client";

import { useAppActions } from "@/store/app-store";
import { PlusIcon } from "@/components/ui/icons";

/** Floating add-expense button (home + activity screens). */
export function Fab() {
  const { openOverlay } = useAppActions();
  return (
    <button
      type="button"
      onClick={() => openOverlay("add")}
      aria-label="Add expense"
      className="absolute bottom-[106px] right-5 z-[15] flex h-[54px] w-[54px] items-center justify-center rounded-[18px] !bg-green !text-white shadow-[0_12px_28px_-8px_rgba(31,157,99,0.6)]"
    >
      <PlusIcon />
    </button>
  );
}
