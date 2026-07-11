"use client";

import { useAppActions } from "@/store/app-store";
import { Sheet } from "@/components/ui/Sheet";
import { NewCategoryForm } from "@/components/forms/NewCategoryForm";

export function NewCategorySheet() {
  const { closeOverlay } = useAppActions();
  return (
    <Sheet onClose={closeOverlay} title="New category">
      <NewCategoryForm />
    </Sheet>
  );
}
