"use client";

import { useAppActions } from "@/store/app-store";
import { Sheet } from "@/components/ui/Sheet";
import { AddRecurringForm } from "@/components/forms/AddRecurringForm";

export function AddRecurringSheet() {
  const { closeOverlay } = useAppActions();
  return (
    <Sheet onClose={closeOverlay} title="Add recurring">
      <AddRecurringForm fillFrequency />
    </Sheet>
  );
}
